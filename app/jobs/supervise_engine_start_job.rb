# Follows the engine start from beginning to end. Resumable: if the worker
# dies, Solid Queue re-enqueues it and the job re-evaluates the real cluster
# state instead of assuming where it left off.
class SuperviseEngineStartJob < ApplicationJob
  queue_as :maintenance

  POLL_INTERVAL = ENV.fetch("TRINO_START_POLL_SECONDS", "5").to_i.seconds

  # Ensures the Trino cluster exists, waits until it is ready, then marks the
  # engine up and releases pending executions. On failure it retries or marks
  # the engine failed, failing every pending execution.
  def perform
    state = TrinoEngineSupervisor.state
    return unless state.status == "starting"

    state.increment!(:start_attempts)

    ensure_cluster_present
    wait_until_ready!

    state.update!(status: "up", last_error: nil, status_changed_at: Time.current)
    TrinoEngineSupervisor.release_pending!
  rescue TrinoProvisioner::Error, Timeout::Error => e
    handle_start_failure(state, e)
  end

  private

  # A cluster that exists and is sick is worse than one that is absent:
  # destroy and recreate.
  def ensure_cluster_present
    if TrinoProvisioner.exists?
      return if TrinoProvisioner.healthy?

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
  # while attempts remain, otherwise marks the engine failed, records an error
  # event, alerts Slack, and fails every pending execution.
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
      AlertChannelNotifier.notify(
        subject: "Trino failed to start",
        message: "Trino failed to start after #{state.start_attempts} attempts: #{error.message}",
        severity: "critical",
        context: { attempts: state.start_attempts, error: error.message }
      )
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
