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

  # Releases everything that was waiting for the engine, from both sources.
  def release_pending!
    ExecutionHistory.where(status: "pending").find_each do |execution|
      MaintenanceOrchestrator.start_execution_on_engine(execution.id)
    end
    FreshnessRun.where(status: "pending").find_each do |run|
      MaintenanceOrchestrator.start_freshness_sweep(run.id)
    end
  end

  def transition!(record, status, **extra)
    record.update!(status: status, status_changed_at: Time.current,
                   generation: record.generation + 1, **extra)
    ActivityBroadcaster.broadcast!
  end
end
