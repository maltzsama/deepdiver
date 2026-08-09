class ScaleUpJob < ApplicationJob
  queue_as :maintenance
  SCALE_UP_TIMEOUT = 10.minutes

  def perform(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)
    execution.update!(current_step: :scale_up)

    if exceeded_timeout?(execution)
      ExecutionFailureHandler.handle(execution, "Trino did not become ready within #{SCALE_UP_TIMEOUT}")
      return
    end

    if TrinoRuntime.ready?
      MaintenanceOrchestrator.execute_maintenance(execution.id)
    else
      TrinoRuntime.ensure_running
      MaintenanceOrchestrator.retry_scale_up(execution.id)
    end
  rescue StandardError => e
    ExecutionFailureHandler.handle(execution, e.message)
  ensure
    guard_trino_down(execution) if execution
  end

  private

  def exceeded_timeout?(execution)
    Time.current - execution.created_at >= SCALE_UP_TIMEOUT
  end

  # Unexpected exit while scaling: make sure the engine is not left running.
  def guard_trino_down(execution)
    return if execution.finished?

    MaintenanceOrchestrator.scale_down(execution.id)
  end
end
