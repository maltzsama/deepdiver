require "test_helper"

class ScheduleDispatchJobTest < ActiveSupport::TestCase
  test "enqueues runs only for matching, non-paused schedules" do
    due = build_schedule(cron: "* * * * *")
    not_due = build_schedule(operation: "expire_snapshots", cron: "0 0 1 1 *")
    paused = build_schedule(operation: "optimize_manifests", cron: "* * * * *", is_paused: true)

    ScheduleDispatchJob.perform_now

    assert_enqueued_jobs 1, only: TrinoManagerJob
    assert_equal 1, due.execution_histories.count
    assert_equal 0, not_due.execution_histories.count
    assert_equal 0, paused.execution_histories.count
  end
end
