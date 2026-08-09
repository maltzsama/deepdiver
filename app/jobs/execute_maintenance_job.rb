class ExecuteMaintenanceJob < ApplicationJob
  queue_as :maintenance

  MAX_RETRIES = 3
  RETRY_WAIT = 10.minutes

  # Step 3: sends the maintenance SQL to Trino. Whatever happens while the engine
  # is up, the runtime is released back (see guard_trino_down below).
  def perform(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)
    execution.update!(current_step: :executing_sql)

    schedule = execution.maintenance_schedule
    sql = MaintenanceSqlBuilder.build(schedule)
    result = TrinoRuntime.execute(sql, execution_id: execution.id)

    execution.update!(status: :success, current_step: :scale_down, metrics: result)
    MaintenanceOrchestrator.scale_down(execution.id)
  rescue TrinoRuntime::CommitConflict => e
    handle_commit_conflict(execution, e)
  rescue StandardError => e
    ExecutionFailureHandler.handle(execution, e.message)
  ensure
    guard_trino_down(execution) if execution
  end

  private

  def guard_trino_down(execution)
    return if execution.finished?

    MaintenanceOrchestrator.scale_down(execution.id)
  end

  # Another engine committed to the table while we were running. Retry, but
  # never more than MAX_RETRIES times; schedule is paused after that.
  def handle_commit_conflict(execution, _error)
    if execution.retry_count >= MAX_RETRIES
      ExecutionFailureHandler.handle(execution, "max retries (#{MAX_RETRIES}) reached after commit conflicts")
    else
      execution.increment!(:retry_count)
      MaintenanceOrchestrator.retry_maintenance(execution.id)
    end
  end
end
