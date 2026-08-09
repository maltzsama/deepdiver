require "test_helper"

class ScaleUpJobTest < ActiveSupport::TestCase
  test "re-enqueues itself with backoff while the runtime is not ready" do
    execution = build_schedule.execution_histories.create!(status: :running, current_step: :scale_up)
    TrinoRuntime.adapter = UnavailableRuntime.new

    ScaleUpJob.perform_now(execution.id)

    execution.reload
    assert_equal "running", execution.status
    assert_enqueued_with(job: ScaleUpJob, args: [ execution.id ])
  end

  test "moves on to maintenance once the runtime is ready" do
    execution = build_schedule.execution_histories.create!(status: :running, current_step: :scale_up)

    ScaleUpJob.perform_now(execution.id)

    assert_enqueued_with(job: ExecuteMaintenanceJob, args: [ execution.id ])
  end

  test "fails and scales down when the 10-minute timeout is exceeded" do
    execution = build_schedule.execution_histories.create!(status: :running, current_step: :scale_up)
    execution.update!(created_at: (ScaleUpJob::SCALE_UP_TIMEOUT + 1.minute).ago)

    ScaleUpJob.perform_now(execution.id)

    execution.reload
    assert_equal "failed", execution.status
    assert_enqueued_with(job: ScaleDownJob, args: [ execution.id ])
  end
end
