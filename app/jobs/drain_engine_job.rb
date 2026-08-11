# Drains and destroys the engine. Deliberately idempotent: it re-evaluates
# demand before acting, so work arriving during the grace period makes any
# scheduled job cancellation unnecessary.
class DrainEngineJob < ApplicationJob
  queue_as :maintenance

  POLL_INTERVAL = ENV.fetch("TRINO_DRAIN_POLL_SECONDS", "10").to_i.seconds

  # Polls the engine while it is draining, waiting for the grace period to
  # elapse or all work to finish, then transitions to stopping and destroys
  # the engine. No-op unless the engine is currently draining.
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

    destroy_engine
  end

  private

  # Returns whether the engine is still in the draining state, re-reading the
  # persisted state so the loop notices if work has arrived.
  # @return [Boolean] true while the engine status is "draining".
  def still_draining?
    TrinoEngineSupervisor.state.reload.status == "draining"
  end

  # If the destruction itself fails, do not leave the state in "stopping"
  # forever: log it and mark the engine failed so the operator can act.
  def destroy_engine
    TrinoProvisioner.destroy!
    TrinoEngineSupervisor.finish_stopping!
  rescue StandardError => e
    Rails.logger.error("Trino destroy failed: #{e.message}")
    TrinoEngineSupervisor.state.with_lock do |current|
      TrinoEngineSupervisor.transition!(current, "failed", last_error: e.message)
    end
  end
end
