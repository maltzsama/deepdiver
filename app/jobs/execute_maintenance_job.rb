# Runs a single step of a maintenance execution and enqueues the next one,
# chaining through the materialised plan until every step has finished.
class ExecuteMaintenanceJob < ApplicationJob
  queue_as :maintenance

  MAX_RETRIES = 3
  RETRY_WAIT = 10.minutes

  # Runs ONE step and enqueues the next. The engine is NOT brought down between
  # steps - the TrinoEngineSupervisor owns that. The chain was materialised by
  # run_plan with each step's cadence already resolved; order is always
  # maintenance_steps.position.
  # @param execution_history_id [Integer] the id of the execution being worked through.
  def perform(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)
    execution.update!(started_at: Time.current) if execution.started_at.nil?

    step = next_step_for(execution)

    return finish_chain(execution) if step.nil?

    run_step(execution, step)
  end

  private

  # Finds the next pending step for the execution, ordered by the maintenance
  # plan's position.
  # @param execution [ExecutionHistory] the execution whose steps are inspected.
  # @return [ExecutionStep, nil] the next pending step, or nil when none remain.
  def next_step_for(execution)
    execution.execution_steps
             .joins(:maintenance_step)
             .where(status: "pending")
             .order("maintenance_steps.position ASC")
             .first
  end

  # Marks the step running, executes its SQL on Trino, records the result, and
  # enqueues the next step. Fails the step and notifies the supervisor on error,
  # retrying on commit conflicts.
  # @param execution [ExecutionHistory] the execution owning the step.
  # @param result_row [ExecutionStep] the step record to run.
  def run_step(execution, result_row)
    maintenance_step = result_row.maintenance_step
    result_row.update!(status: "running", started_at: Time.current)
    execution.update!(current_step: result_row.operation)

    sql = MaintenanceSqlBuilder.build(execution.iceberg_table, maintenance_step)
    metrics = TrinoRuntime.execute(sql, execution_id: execution.id, execution: execution)

    result_row.update!(status: "succeeded", finished_at: Time.current, metrics: metrics)
    maintenance_step&.update_column(:last_run_at, Time.current)
    ActivityBroadcaster.broadcast!

    # Next link in the chain.
    MaintenanceOrchestrator.execute_maintenance(execution.id)
  rescue TrinoRuntime::CommitConflict => e
    handle_commit_conflict(execution, result_row, e)
  rescue StandardError => e
    result_row&.update!(status: "failed", finished_at: Time.current, error_message: e.message)
    ExecutionFailureHandler.handle(execution, "#{result_row.operation}: #{e.message}")
    # The handler marked the execution failed, so demand may have dropped to
    # zero - let the supervisor evaluate whether the engine can drain.
    TrinoEngineSupervisor.demand_finished!
  end

  # Handles a Trino commit conflict on a step: fails it after the retry limit,
  # otherwise increments the retry counter and re-enqueues the execution.
  # @param execution [ExecutionHistory] the execution owning the step.
  # @param result_row [ExecutionStep] the step that hit the conflict.
  # @param error [TrinoRuntime::CommitConflict] the raised conflict error.
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

  # Marks the execution successful, resets the plan's failure counter, and
  # notifies the supervisor that demand has finished.
  # @param execution [ExecutionHistory] the execution that just completed.
  def finish_chain(execution)
    execution.update!(status: :success, current_step: "done", finished_at: Time.current)
    execution.maintenance_plan.update!(consecutive_failures: 0)
    TrinoEngineSupervisor.demand_finished!
  end
end
