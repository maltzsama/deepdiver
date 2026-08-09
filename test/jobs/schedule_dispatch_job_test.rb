require "test_helper"

class ScheduleDispatchJobTest < ActiveSupport::TestCase
  test "enqueues runs only for matching, non-paused schedules" do
    due = build_schedule(cron: "* * * * *")
    not_due = build_schedule(operation: "expire_snapshots", cron: "0 0 1 1 *")
    paused = build_schedule(operation: "optimize_manifests", cron: "* * * * *", is_paused: true)

    ScheduleDispatchJob.perform_now

    # The engine was down, so the dispatch kicked off a supervised start.
    assert_enqueued_jobs 1, only: SuperviseEngineStartJob
    assert_equal 1, due.execution_histories.count
    assert_equal 0, not_due.execution_histories.count
    assert_equal 0, paused.execution_histories.count
  end

  test "one failing schedule does not prevent later schedules from dispatching" do
    first = build_schedule(cron: "* * * * *")
    second = build_schedule(operation: "expire_snapshots", cron: "* * * * *")

    original = MaintenanceOrchestrator.method(:run_schedule)
    MaintenanceOrchestrator.define_singleton_method(:run_schedule) do |schedule_id|
      raise "boom" if schedule_id == first.id

      original.call(schedule_id)
    end

    ScheduleDispatchJob.perform_now

    second_execution = second.execution_histories.first
    assert second_execution
    assert_equal 0, first.execution_histories.count
    assert_enqueued_with(job: SuperviseEngineStartJob)
  ensure
    MaintenanceOrchestrator.singleton_class.send(:remove_method, :run_schedule) if original
    MaintenanceOrchestrator.define_singleton_method(:run_schedule, original) if original
  end
end
