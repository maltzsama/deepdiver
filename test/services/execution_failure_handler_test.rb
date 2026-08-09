require "test_helper"

class ExecutionFailureHandlerTest < ActiveSupport::TestCase
  test "marks the execution failed, records the message and frees the table lock" do
    schedule = build_schedule
    execution = schedule.execution_histories.create!(status: :running, current_step: :executing_sql)
    TableLock.acquire(execution)

    ExecutionFailureHandler.handle(execution, "boom")

    execution.reload
    assert_equal "failed", execution.status
    assert_equal "boom", execution.error_message
    assert_equal 1, schedule.reload.consecutive_failures
    assert_equal 0, TableLock.count
    assert_enqueued_jobs 0
  end

  test "pauses the schedule after 3 consecutive failures" do
    schedule = build_schedule
    schedule.update!(consecutive_failures: 2)
    execution = schedule.execution_histories.create!(status: :running, current_step: :executing_sql)

    ExecutionFailureHandler.handle(execution, "third strike")

    assert_equal true, schedule.reload.paused?
  end
end
