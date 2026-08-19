# Event-driven lifecycle of the engine, safe with TWO demand sources
# (maintenance executions and freshness sweeps).
#
# Every transition happens under a row lock (SELECT ... FOR UPDATE on the
# single trino_engine_states row), which closes three races at once: the
# destroy-during-acceptance window, concurrent drains and concurrent starts.
#
# State machine: down -> starting -> up -> draining -> stopping -> down.
# "stopping" is the point of no return: destruction is in progress, and demand
# that arrives there must wait for down and trigger a fresh start.
module TrinoEngineSupervisor
  READY_TIMEOUT = ENV.fetch("TRINO_READY_TIMEOUT_MINUTES", "8").to_i.minutes
  MAX_START_ATTEMPTS = ENV.fetch("TRINO_MAX_START_ATTEMPTS", "2").to_i
  DRAIN_GRACE = ENV.fetch("TRINO_DRAIN_GRACE_MINUTES", "5").to_i.minutes

  module_function

  # Returns the single engine-state row, creating it on first use.
  #
  # @return [TrinoEngineState] the state row
  def state = TrinoEngineState.first_or_create!(status: "down", status_changed_at: Time.current)

  # Single entry point for ANY demand source. Maintenance and freshness call
  # the same method - there is no parallel path that could diverge.
  def demand_arrived!(dispatch: nil)
    current = state
    current.with_lock do
      case current.status
      when "up"
        dispatch&.call
      when "starting"
        # The start in progress releases everything pending when ready.
        nil
      when "draining"
        # Still in time: back up without destroying anything.
        transition!(current, "up", drain_started_at: nil)
        dispatch&.call
      when "stopping"
        # Destruction already in progress. Do NOT dispatch: the engine is
        # dying. When it reaches down, the pending demand triggers a new start.
        nil
      else # down | failed
        transition!(current, "starting", start_attempts: 0, last_error: nil)
        MaintenanceOrchestrator.supervise_engine_start
      end
    end
  end

  # Marks the engine draining when demand ends while it is up.
  def demand_finished!
    current = state
    current.with_lock do
      next if TrinoDemand.any?
      next unless current.status == "up"

      transition!(current, "draining", drain_started_at: Time.current)
      MaintenanceOrchestrator.drain_engine
    end
  end

  # Called by DrainEngineJob immediately before destroying. Returns false if
  # demand appeared - and then the destruction does NOT happen.
  def begin_stopping!
    current = state
    current.with_lock do
      return false unless current.status == "draining"

      if TrinoDemand.any?
        transition!(current, "up", drain_started_at: nil)
        release_pending!
        return false
      end

      transition!(current, "stopping")
      true
    end
  end

  # Called after the destruction finished.
  def finish_stopping!
    current = state
    current.with_lock do
      transition!(current, "down", drain_started_at: nil)

      # Demand that arrived during stopping: start again now.
      if TrinoDemand.any?
        transition!(current, "starting", start_attempts: 0)
        MaintenanceOrchestrator.supervise_engine_start
      end
    end
  end

  # Operator-forced restart from the activity screen.
  def restart!
    current = state
    current.with_lock do
      transition!(current, "starting", start_attempts: 0, last_error: nil)
      MaintenanceOrchestrator.supervise_engine_start
    end
  end

  # Hard reset for a frozen engine: fails everything in flight, clears the
  # whole job queue, tears the Trino cluster down, and returns the engine to
  # "down". Used from the activity screen when the engine stops making progress
  # and a plain restart is not enough.
  def hard_reset!
    state.with_lock do
      fail_in_flight!
      begin
        SolidQueue::Job.where(finished_at: nil).delete_all
      rescue StandardError
        nil # queue DB may not be provisioned in dev/test
      end
      transition!(state, "down", start_attempts: 0, last_error: nil, drain_started_at: nil) unless state.status == "down"
    end

    TrinoProvisioner.destroy! rescue nil
    TrinoProvisioner.wait_gone!(timeout: 2.minutes) rescue nil
    ActivityBroadcaster.broadcast!
  end

  # Frees every execution currently in flight, releasing their table locks so
  # nothing is left dangling after a hard reset. Freshness runs are failed too.
  def fail_in_flight!
    ExecutionHistory.where(status: %w[pending running]).find_each do |execution|
      TableLock.release(execution)
      execution.update!(status: :failed, current_step: "start",
                        finished_at: Time.current, error_message: "engine hard reset")
    end
    FreshnessRun.where(status: %w[pending running]).find_each do |run|
      run.update!(status: "failed", finished_at: Time.current, error_message: "engine hard reset")
    end
  end

  # Releases everything that was waiting for the engine, from both sources.
  def release_pending!
    ExecutionHistory.where(status: "pending").find_each do |execution|
      MaintenanceOrchestrator.start_execution_on_engine(execution.id)
    end
    FreshnessRun.where(status: "pending").find_each do |run|
      MaintenanceOrchestrator.start_freshness_sweep(run.id)
    end
  end

  # Persists a state transition, records it as an engine lifecycle event, and
  # broadcasts the new engine activity.
  #
  # @param record [TrinoEngineState] the state row
  # @param status [String] the target status
  # @param extra [Hash] additional attributes to write
  def transition!(record, status, **extra)
    record.update!(status: status, status_changed_at: Time.current,
                   generation: record.generation + 1, **extra)
    record_lifecycle!(record, status)
    ActivityBroadcaster.broadcast!
  end

  # Records the transition as an info-level engine event so the activity screen
  # can show when the cluster went up, down, draining, etc. Genuine failures are
  # recorded separately with severity "error" by the jobs that detect them.
  #
  # These are informational markers, not actionable errors, so they are recorded
  # already resolved - otherwise every start/stop would pile up as an "open
  # error" on the error surface.
  #
  # The generation is part of the message: ErrorEvent dedupes by message, and the
  # timeline needs every up/down to be its own event rather than one counter.
  #
  # @param record [TrinoEngineState] the state row after the transition
  # @param status [String] the new status
  def record_lifecycle!(record, status)
    ErrorEvent.record(
      catalog: nil, schema: "engine", operation: "engine-lifecycle",
      source_system: "engine", severity: "info", status: "resolved",
      message: "engine #{status} (generation #{record.generation})",
      context: { attempts: record.start_attempts, generation: record.generation, state: status }
    )
  end
  private_class_method :record_lifecycle!
end
