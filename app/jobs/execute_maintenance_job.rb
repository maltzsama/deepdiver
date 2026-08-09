class ExecuteMaintenanceJob < ApplicationJob
  queue_as :maintenance

  MAX_RETRIES = 3
  RETRY_WAIT = 10.minutes

  # Runs ONE step and enqueues the next. The engine is NOT brought down between
  # steps - the TrinoEngineSupervisor owns that.
  def perform(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)
    execution.update!(started_at: Time.current) if execution.started_at.nil?

    step = next_step_for(execution)

    return finish_chain(execution) if step.nil?

    run_step(execution, step)
  end

  private

  def next_step_for(execution)
    done = execution.execution_steps.where(status: %w[succeeded skipped]).pluck(:operation)

    execution.maintenance_plan.maintenance_steps.find do |candidate|
      !done.include?(candidate.operation)
    end
  end

  def run_step(execution, step)
    unless step.enabled
      execution.execution_steps.create!(operation: step.operation, maintenance_step: step,
                                        status: "skipped")
      return MaintenanceOrchestrator.execute_maintenance(execution.id)
    end

    result_row = execution.execution_steps.find_or_create_by!(operation: step.operation) do |row|
      row.maintenance_step = step
    end
    result_row.update!(status: "running", started_at: Time.current)
    execution.update!(current_step: step.operation)

    sql = MaintenanceSqlBuilder.build(execution.iceberg_table, step)
    metrics = TrinoRuntime.execute(sql, execution_id: execution.id, execution: execution)

    result_row.update!(status: "succeeded", finished_at: Time.current, metrics: metrics)

    # Next link in the chain.
    MaintenanceOrchestrator.execute_maintenance(execution.id)
  rescue TrinoRuntime::CommitConflict => e
    handle_commit_conflict(execution, result_row, e)
  rescue StandardError => e
    result_row&.update!(status: "failed", finished_at: Time.current, error_message: e.message)
    ExecutionFailureHandler.handle(execution, "#{step.operation}: #{e.message}")
  end

  def handle_commit_conflict(execution, result_row, error)
    if result_row.retry_count >= MAX_RETRIES
      result_row.update!(status: "failed", finished_at: Time.current,
                         error_message: "commit conflict after #{MAX_RETRIES} attempts")
      ExecutionFailureHandler.handle(execution, "commit conflict in #{result_row.operation}")
    else
      result_row.increment!(:retry_count)
      # The execution stays "running", so it keeps counting as demand: the
      # engine stays up on its own during the wait.
      MaintenanceOrchestrator.retry_maintenance(execution.id)
    end
  end

  def finish_chain(execution)
    execution.update!(status: :success, current_step: "done", finished_at: Time.current)
    execution.maintenance_plan.update!(consecutive_failures: 0)
    TrinoEngineSupervisor.on_execution_finished(execution)
  end
end
