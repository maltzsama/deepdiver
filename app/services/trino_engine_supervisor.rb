# Event-driven lifecycle of the engine.
#
# Comes up when work arrives and the engine is down.
# Drains when demand reaches zero.
# There is NO recurring job: whoever asks for a start follows it to the end.
module TrinoEngineSupervisor
  READY_TIMEOUT = 8.minutes
  MAX_START_ATTEMPTS = 2
  DRAIN_GRACE = 5.minutes

  module_function

  def state
    TrinoEngineState.first_or_create!(status: "down", status_changed_at: Time.current)
  end

  # Called when an execution is enqueued.
  def on_execution_enqueued(execution)
    current = state

    case current.status
    when "up"
      MaintenanceOrchestrator.start_execution_on_engine(execution.id)
    when "starting"
      # Someone is already supervising the start; this execution will be
      # released together with the rest when the engine is ready.
      nil
    when "draining"
      # Work arrived within the grace period: cancel the drain without
      # bringing the engine down.
      current.update!(status: "up", drain_started_at: nil, status_changed_at: Time.current)
      MaintenanceOrchestrator.start_execution_on_engine(execution.id)
    else # down | failed
      current.update!(status: "starting", start_attempts: 0,
                      last_error: nil, status_changed_at: Time.current)
      MaintenanceOrchestrator.supervise_engine_start
    end
  end

  # Called when an execution finishes (success or failure).
  def on_execution_finished(execution)
    TableLock.release(execution)

    return if TrinoDemand.any?

    current = state
    return unless current.status == "up"

    current.update!(status: "draining", drain_started_at: Time.current,
                    status_changed_at: Time.current)
    MaintenanceOrchestrator.drain_engine
  end

  # Releases all the executions that were waiting for the engine.
  def release_pending!
    ExecutionHistory.where(status: "pending").find_each do |execution|
      MaintenanceOrchestrator.start_execution_on_engine(execution.id)
    end
  end
end
