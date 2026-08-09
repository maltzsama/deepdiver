# Recurring entry point (see config/recurring.yml). Creates the freshness run,
# signals the supervisor that the engine is needed, and dispatches the sweep.
class EnqueueFreshnessSweepJob < ApplicationJob
  queue_as :freshness

  def perform
    run = FreshnessRun.create!(status: "pending")

    if TableFreshnessSla.where(enabled: true).none?
      run.update!(status: "finished", finished_at: Time.current)
      return
    end

    TrinoEngineSupervisor.on_freshness_run_enqueued(run)
    FreshnessSweepJob.perform_later(run.id)
  end
end
