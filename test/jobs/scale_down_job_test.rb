require "test_helper"

class ScaleDownJobTest < ActiveSupport::TestCase
  test "releases the lock and marks the execution done" do
    schedule = build_schedule
    execution = schedule.execution_histories.create!(status: :running, current_step: :scale_down)
    TrinoLock.acquire(execution.id)

    ScaleDownJob.perform_now(execution.id)

    execution.reload
    assert_equal "done", execution.current_step
    assert_equal 0, TrinoLock.count
  end

  test "is idempotent when there is no lock" do
    schedule = build_schedule
    execution = schedule.execution_histories.create!(status: :running, current_step: :scale_down)

    assert_nothing_raised { ScaleDownJob.perform_now(execution.id) }

    execution.reload
    assert_equal "done", execution.current_step
  end
end
