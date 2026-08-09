require "test_helper"

class ScheduleDispatchJobTest < ActiveSupport::TestCase
  test "enqueues runs only for matching, non-paused plans" do
    due = build_plan(cron: "* * * * *")
    not_due = build_plan(cron: "0 0 1 1 *")
    paused = build_plan(cron: "* * * * *", is_paused: true)

    ScheduleDispatchJob.perform_now

    # The engine was down, so the dispatch kicked off a supervised start.
    assert_enqueued_jobs 1, only: SuperviseEngineStartJob
    assert_equal 1, due.execution_histories.count
    assert_equal 0, not_due.execution_histories.count
    assert_equal 0, paused.execution_histories.count
  end

  test "one failing plan does not prevent later plans from dispatching" do
    first = build_plan(cron: "* * * * *")
    second = build_plan(cron: "* * * * *")

    original = MaintenanceOrchestrator.method(:run_plan)
    MaintenanceOrchestrator.define_singleton_method(:run_plan) do |plan_id|
      raise "boom" if plan_id == first.id

      original.call(plan_id)
    end

    ScheduleDispatchJob.perform_now

    second_execution = second.execution_histories.first
    assert second_execution
    assert_equal 0, first.execution_histories.count
    assert_enqueued_with(job: SuperviseEngineStartJob)
  ensure
    MaintenanceOrchestrator.singleton_class.send(:remove_method, :run_plan) if original
    MaintenanceOrchestrator.define_singleton_method(:run_plan, original) if original
  end
end
