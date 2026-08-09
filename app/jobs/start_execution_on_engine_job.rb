# Releases a pending execution onto the engine: acquires the per-table lock
# and, when successful, enqueues the maintenance. Re-enqueued with a wait on
# lock contention (another execution owns the same table).
class StartExecutionOnEngineJob < ApplicationJob
  queue_as :maintenance

  def perform(execution_history_id)
    MaintenanceOrchestrator.start_execution_on_engine(execution_history_id)
  end
end
