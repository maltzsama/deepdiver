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

  class BrokenStopRuntime < FakeTrinoRuntime
    def ensure_stopped
      raise "k8s unavailable"
    end
  end

  test "keeps a successful status when only the teardown fails" do
    execution = build_schedule.execution_histories.create!(status: :success, current_step: :scale_down)
    TrinoRuntime.adapter = BrokenStopRuntime.new

    assert_raises(RuntimeError) { ScaleDownJob.perform_now(execution.id) }

    execution.reload
    assert_equal "success", execution.status
    assert_match(/scale down failed/, execution.error_message)
  end

  test "records a failed teardown on a non-successful execution" do
    execution = build_schedule.execution_histories.create!(status: :running, current_step: :scale_down)
    TrinoRuntime.adapter = BrokenStopRuntime.new

    assert_raises(RuntimeError) { ScaleDownJob.perform_now(execution.id) }

    execution.reload
    assert_equal "failed", execution.status
    assert_match(/scale down failed/, execution.error_message)
  end

  test "returns silently when the execution has been deleted" do
    assert_nothing_raised { ScaleDownJob.perform_now(999_999_999) }
  end
end
