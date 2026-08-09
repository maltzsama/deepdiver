require "test_helper"

class TrinoManagerJobTest < ActiveSupport::TestCase
  # perform_enqueued_jobs only runs the jobs enqueued at call time; the state
  # machine enqueues its next steps while executing, so drain until empty.
  def drain_enqueued_jobs
    until enqueued_jobs.empty?
      perform_enqueued_jobs
    end
  end
  test "runs the whole maintenance state machine to completion" do
    schedule = build_schedule

    execution = MaintenanceOrchestrator.run_schedule(schedule.id)

    assert_enqueued_with(job: TrinoManagerJob, args: [ execution.id ])
    drain_enqueued_jobs

    execution.reload
    assert_equal "success", execution.status
    assert_equal "done", execution.current_step
    assert_equal 0, TrinoLock.count
  end

  test "does not start two executions concurrently" do
    schedule = build_schedule
    first = schedule.execution_histories.create!(status: :running, current_step: :start)
    second = schedule.execution_histories.create!(status: :running, current_step: :start)

    assert TrinoLock.acquire(first.id)
    TrinoManagerJob.perform_now(second.id)

    # The second execution did not grab the lock; it re-queued a retry instead.
    assert_enqueued_with(job: TrinoManagerJob, args: [ second.id ])
    assert_equal 1, TrinoLock.count
  end
end
