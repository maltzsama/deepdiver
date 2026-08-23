# Follows the engine start from beginning to end. Resumable: if the worker
# dies, Solid Queue re-enqueues it and the job re-evaluates the real cluster
# state instead of assuming where it left off.
class SuperviseEngineStartJob < ApplicationJob
  queue_as :engine

  POLL_INTERVAL = ENV.fetch("TRINO_START_POLL_SECONDS", "5").to_i.seconds

  # Ensures the Trino cluster exists, waits until it is ready, marks the engine
  # up (recording the transition and broadcasting it), then releases pending
  # executions.
  def perform
    state = TrinoEngineSupervisor.state
    return unless state.status == "starting"

    state.increment!(:start_attempts)

    ensure_cluster_present
    wait_until_ready!

    TrinoEngineSupervisor.transition!(state, "up", last_error: nil)
    TrinoEngineSupervisor.release_pending!

    # All demand may have been cancelled while we were booting. Re-evaluate.
    TrinoEngineSupervisor.demand_finished!
  rescue TrinoEngineSupervisor::ConcurrentTransitionError
    nil
  rescue TrinoProvisioner::Error, Timeout::Error => e
    handle_start_failure(state, e)
  end

  private

  # A cluster that is up but sick is worse than one that is absent: destroy and
  # recreate. A cluster scaled to 0 (just drained) is simply off - bring it up.
  def ensure_cluster_present
    if TrinoProvisioner.exists? && TrinoProvisioner.replicas.positive? && !TrinoProvisioner.healthy?
      Rails.logger.warn("Existing Trino in bad state; destroying before recreating")
      TrinoProvisioner.destroy!
      TrinoProvisioner.wait_gone!(timeout: 2.minutes)
    end

    TrinoProvisioner.create!
  end

  # Polls until the cluster rollout is complete and healthy, raising a
  # Timeout::Error if readiness takes longer than the configured timeout.
  def wait_until_ready!
    deadline = Time.current + TrinoEngineSupervisor::READY_TIMEOUT

    loop do
      raise Timeout::Error, "Trino not ready within #{TrinoEngineSupervisor::READY_TIMEOUT.inspect}" if Time.current > deadline
      return if TrinoProvisioner.rollout_complete? && TrinoProvisioner.healthy?

      sleep POLL_INTERVAL
    end
  end

  # Reacts to a failed start: re-enqueues supervision and recreates the cluster
  # while attempts remain, otherwise marks the engine failed and records an
  # error event.
  # @param state [TrinoEngineSupervisorState] the current engine state.
  # @param error [Exception] the error that caused the failure.
  def handle_start_failure(state, error)
    if state.start_attempts < TrinoEngineSupervisor::MAX_START_ATTEMPTS
      Rails.logger.warn("Trino start failed (attempt #{state.start_attempts}): #{error.message}")
      TrinoProvisioner.destroy! rescue nil
      MaintenanceOrchestrator.supervise_engine_start
    else
      state.update!(status: "failed", last_error: error.message, status_changed_at: Time.current)
      ErrorEvent.record(catalog: nil, schema: "engine", operation: "engine-start",
                        source_system: "engine", error_class: error.class.name, message: error.message)
      fail_pending_executions!(error.message)
    end
  end

  # Fails every pending execution with the given message and signals the
  # supervisor that demand has finished so it can re-evaluate the state.
  # @param message [String] the failure reason to record on each execution.
  def fail_pending_executions!(message)
    ExecutionHistory.where(status: "pending").find_each do |execution|
      ExecutionFailureHandler.handle(execution, "engine unavailable: #{message}")
    end
    # The engine never came up and every pending execution just failed: demand
    # dropped to zero, so there is nothing to drain - but let the supervisor
    # re-evaluate the state under its lock.
    TrinoEngineSupervisor.demand_finished!
  end
end
