# Detects engines stuck in "starting" or "draining" for longer than the
# configured timeouts and marks them failed so the operator can act.
class EngineWatchdogJob < ApplicationJob
  queue_as :engine

  # The retry path (SuperviseEngineStartJob#handle_start_failure) re-enqueues
  # supervision up to MAX_START_ATTEMPTS times WITHOUT renewing status_changed_at
  # (it only bumps start_attempts). Each attempt gets its own READY_TIMEOUT, so
  # the legitimate start window spans ALL attempts — a single-attempt window
  # would let the watchdog fail a start that is still legitimately retrying.
  START_STUCK_AFTER = (TrinoEngineSupervisor::READY_TIMEOUT * TrinoEngineSupervisor::MAX_START_ATTEMPTS) + 2.minutes
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
