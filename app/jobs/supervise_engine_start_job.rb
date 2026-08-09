# Follows the engine start from beginning to end. Resumable: if the worker
# dies, Solid Queue re-enqueues it and the job re-evaluates the real cluster
# state instead of assuming where it left off.
class SuperviseEngineStartJob < ApplicationJob
  queue_as :maintenance

  POLL_INTERVAL = 5.seconds

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

  def wait_until_ready!
    deadline = Time.current + TrinoEngineSupervisor::READY_TIMEOUT

    loop do
      raise Timeout::Error, "Trino not ready within #{TrinoEngineSupervisor::READY_TIMEOUT.inspect}" if Time.current > deadline
      return if TrinoProvisioner.rollout_complete? && TrinoProvisioner.healthy?

      sleep POLL_INTERVAL
    end
  end

  def handle_start_failure(state, error)
    if state.start_attempts < TrinoEngineSupervisor::MAX_START_ATTEMPTS
      Rails.logger.warn("Trino start failed (attempt #{state.start_attempts}): #{error.message}")
      TrinoProvisioner.destroy! rescue nil
      MaintenanceOrchestrator.supervise_engine_start
    else
      state.update!(status: "failed", last_error: error.message, status_changed_at: Time.current)
      SlackAlert.notify("Trino failed to start after #{state.start_attempts} attempts: #{error.message}")
      fail_pending_executions!(error.message)
    end
  end

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
