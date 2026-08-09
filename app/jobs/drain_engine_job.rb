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
      # Work arrived: begin_stopping! returns false and already restores to up.
      return unless still_draining?

      break if Time.current > deadline
      break if TrinoProvisioner.idle?

      sleep POLL_INTERVAL
    end

    # Last check and the transition to stopping happen under the SAME lock:
    # after this, new demand waits for down instead of being dispatched.
    return unless TrinoEngineSupervisor.begin_stopping!

    Rails.logger.warn("Drain grace period exhausted with queries still active; destroying anyway") unless TrinoProvisioner.idle?

    TrinoProvisioner.destroy!
    TrinoEngineSupervisor.finish_stopping!
  end

  private

  def still_draining?
    TrinoEngineSupervisor.state.reload.status == "draining"
  end
end
