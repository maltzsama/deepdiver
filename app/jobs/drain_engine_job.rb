# Drains and destroys the engine. Deliberately idempotent: it re-evaluates
# demand before acting, so work arriving during the grace period makes any
# scheduled job cancellation unnecessary.
class DrainEngineJob < ApplicationJob
  queue_as :maintenance

  POLL_INTERVAL = 10.seconds

  def perform
    state = TrinoEngineSupervisor.state
    return unless state.status == "draining"

    deadline = (state.drain_started_at || Time.current) + TrinoEngineSupervisor::DRAIN_GRACE

    loop do
      # New work arrived: abort the drain, keep the engine up.
      if TrinoDemand.any?
        state.update!(status: "up", drain_started_at: nil, status_changed_at: Time.current)
        TrinoEngineSupervisor.release_pending!
        return
      end

      break if Time.current > deadline
      break if TrinoProvisioner.idle?

      sleep POLL_INTERVAL
    end

    unless TrinoProvisioner.idle?
      Rails.logger.warn("Drain grace period exhausted with queries still active; destroying anyway")
    end

    TrinoProvisioner.destroy!
    state.update!(status: "down", drain_started_at: nil, status_changed_at: Time.current)
  end
end
