# Detects engines stuck in "starting" or "draining" for longer than the
# configured timeouts and marks them failed so the operator can act.
class EngineWatchdogJob < ApplicationJob
  queue_as :engine

  START_STUCK_AFTER = TrinoEngineSupervisor::READY_TIMEOUT + 2.minutes
  DRAIN_STUCK_AFTER = TrinoEngineSupervisor::DRAIN_GRACE + 10.minutes

  def perform
    check_stuck("starting", START_STUCK_AFTER, "engine start timed out (watchdog)")
    check_stuck("draining", DRAIN_STUCK_AFTER, "engine drain timed out (watchdog)")
  end

  private

  def check_stuck(status, threshold, message)
    state = TrinoEngineSupervisor.state
    return unless state.status == status
    return if state.status_changed_at > threshold.ago

    Rails.logger.error("Engine stuck in #{status} since #{state.status_changed_at}; marking failed")
    state.with_lock do
      TrinoEngineSupervisor.transition!(state, "failed", last_error: message)
    end
  rescue TrinoEngineSupervisor::ConcurrentTransitionError
    nil
  ensure
    TrinoEngineSupervisor.broadcast_deferred!
  end
end
