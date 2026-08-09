require "test_helper"

class ExecuteMaintenanceJobTest < ActiveSupport::TestCase
  test "a commit conflict bumps the retry_count and enqueues a backoff retry" do
    execution = build_schedule.execution_histories.create!(status: :running, current_step: :executing_sql)
    TrinoRuntime.adapter = ConflictRuntime.new

    ExecuteMaintenanceJob.perform_now(execution.id)

    execution.reload
    assert_equal 1, execution.retry_count
    assert_equal "running", execution.status
    assert_enqueued_with(job: ExecuteMaintenanceJob, args: [ execution.id ])
  end

  test "gives up after the max retries and pauses the schedule" do
    schedule = build_schedule
    schedule.update!(consecutive_failures: 2)
    execution = schedule.execution_histories.create!(status: :running, current_step: :executing_sql,
                                                     retry_count: ExecuteMaintenanceJob::MAX_RETRIES)
    TrinoRuntime.adapter = ConflictRuntime.new

    ExecuteMaintenanceJob.perform_now(execution.id)

    execution.reload
    assert_equal "failed", execution.status
    assert schedule.reload.paused?
    assert_enqueued_with(job: ScaleDownJob, args: [ execution.id ])
  end

  test "a generic failure marks the execution failed and scales down" do
    execution = build_schedule.execution_histories.create!(status: :running, current_step: :executing_sql)
    TrinoRuntime.adapter = Object.new # no `execute` method -> standard error

    ExecuteMaintenanceJob.perform_now(execution.id)

    execution.reload
    assert_equal "failed", execution.status
    assert_match(/undefined method/, execution.error_message)
    assert_enqueued_with(job: ScaleDownJob, args: [ execution.id ])
  end
end
