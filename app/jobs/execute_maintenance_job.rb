class ExecuteMaintenanceJob < ApplicationJob
  queue_as :maintenance

  MAX_RETRIES = 3
  RETRY_WAIT = 10.minutes

  # Sends the maintenance SQL to Trino. The engine is not brought down here:
  # whether it goes up and down is decided by the TrinoEngineSupervisor from
  # demand.
  def perform(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)
    execution.update!(current_step: :executing_sql)

    schedule = execution.maintenance_schedule
    sql = MaintenanceSqlBuilder.build(schedule)
    result = TrinoRuntime.execute(sql, execution_id: execution.id, execution: execution)

    execution.update!(status: :success, current_step: :done, metrics: result)
  rescue TrinoRuntime::CommitConflict => e
    handle_commit_conflict(execution, e)
  rescue StandardError => e
    ExecutionFailureHandler.handle(execution, e.message)
  ensure
    TrinoEngineSupervisor.on_execution_finished(execution) if execution
  end

  private

  # Another engine committed to the table while we were running. Retry, but
  # never more than MAX_RETRIES times; schedule is paused after that. The
  # execution stays "running", so it keeps counting as demand and the engine
  # stays up on its own.
  def handle_commit_conflict(execution, _error)
    if execution.retry_count >= MAX_RETRIES
      ExecutionFailureHandler.handle(execution, "max retries (#{MAX_RETRIES}) reached after commit conflicts")
    else
      execution.increment!(:retry_count)
      MaintenanceOrchestrator.retry_maintenance(execution.id)
    end
  end
end
