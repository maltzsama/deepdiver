require "test_helper"

class ExecuteMaintenanceJobTest < ActiveSupport::TestCase
  def released_execution(plan)
    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))
    execution.update!(status: :running)
    execution
  end

  test "a commit conflict keeps the execution as demand and retries the step" do
    plan = build_plan_with_steps
    execution = released_execution(plan)
    TableLock.acquire(execution)
    TrinoRuntime.adapter = ConflictRuntime.new

    ExecuteMaintenanceJob.perform_now(execution.id)

    execution.reload
    assert_equal "running", execution.status
    assert_equal 1, execution.execution_steps.first.retry_count
    assert_enqueued_with(job: ExecuteMaintenanceJob, args: [ execution.id ])

    # The per-table lock stays held for the whole chain, including the retry.
    assert_equal 1, TableLock.count
  end

  test "gives up after the max retries and pauses the plan" do
    plan = build_plan_with_steps
    plan.update!(consecutive_failures: 2)
    execution = released_execution(plan)
    execution.execution_steps.find_by(operation: "optimize").update!(retry_count: ExecuteMaintenanceJob::MAX_RETRIES)
    TrinoRuntime.adapter = ConflictRuntime.new

    ExecuteMaintenanceJob.perform_now(execution.id)

    execution.reload
    assert_equal "failed", execution.status
    assert_equal "failed", execution.execution_steps.first.status
    assert plan.reload.paused?
  end

  test "a generic failure marks the execution failed" do
    plan = build_plan_with_steps
    execution = released_execution(plan)
    TrinoRuntime.adapter = Object.new # no `execute` method -> standard error

    ExecuteMaintenanceJob.perform_now(execution.id)

    execution.reload
    assert_equal "failed", execution.status
    assert_equal "failed", execution.execution_steps.first.status
    assert_match(/undefined method/, execution.execution_steps.first.error_message)
  end
end
