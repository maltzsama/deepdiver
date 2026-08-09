require "test_helper"

class ExecuteMaintenanceJobTest < ActiveSupport::TestCase
  test "a commit conflict bumps the retry_count and enqueues a backoff retry" do
    schedule = build_schedule
    execution = schedule.execution_histories.create!(status: :running, current_step: :executing_sql)
    TableLock.acquire(execution)
    TrinoRuntime.adapter = ConflictRuntime.new

    ExecuteMaintenanceJob.perform_now(execution.id)

    execution.reload
    assert_equal 1, execution.retry_count
    assert_equal "running", execution.status
    assert_enqueued_with(job: ExecuteMaintenanceJob, args: [ execution.id ])
    assert_no_enqueued_jobs only: DrainEngineJob

    # The execution keeps counting as demand (engine stays up on its own), and
    # the per-table lock is freed so the retry can re-run.
    assert_equal 0, TableLock.count
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
    assert_no_enqueued_jobs only: ExecuteMaintenanceJob
  end

  test "a generic failure marks the execution failed" do
    execution = build_schedule.execution_histories.create!(status: :running, current_step: :executing_sql)
    TrinoRuntime.adapter = Object.new # no `execute` method -> standard error

    ExecuteMaintenanceJob.perform_now(execution.id)

    execution.reload
    assert_equal "failed", execution.status
    assert_match(/undefined method/, execution.error_message)
  end
end
