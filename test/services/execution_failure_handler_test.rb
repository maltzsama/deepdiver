require "test_helper"

class ExecutionFailureHandlerTest < ActiveSupport::TestCase
  test "marks the execution failed, records the message and frees the table lock" do
    plan = build_plan_with_steps
    execution = plan.execution_histories.create!(status: :running, current_step: :start)
    TableLock.acquire(execution)

    ExecutionFailureHandler.handle(execution, "boom")

    execution.reload
    assert_equal "failed", execution.status
    assert_equal "boom", execution.error_message
    assert_equal 1, plan.reload.consecutive_failures
    assert_equal 0, TableLock.count
    assert_enqueued_jobs 0
  end

  test "pauses the plan after the auto-pause threshold of consecutive failures" do
    plan = build_plan_with_steps
    plan.update!(consecutive_failures: 2)
    execution = plan.execution_histories.create!(status: :running, current_step: :start)

    ExecutionFailureHandler.handle(execution, "third strike")

    assert_equal true, plan.reload.paused?
  end
end
