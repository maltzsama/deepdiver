# Recurring entry point (see config/recurring.yml). Delegates to the
# orchestrator, which skips the run entirely when nothing is enabled and
# otherwise creates the run and signals the supervisor.
class EnqueueFreshnessSweepJob < ApplicationJob
  queue_as :freshness

  def perform
    MaintenanceOrchestrator.enqueue_freshness_sweep
  end
end
