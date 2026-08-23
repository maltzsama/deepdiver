# Releases a pending execution onto the engine: acquires the per-table lock
# and, when successful, enqueues the maintenance. Re-enqueued with a wait on
# lock contention (another execution owns the same table).
class StartExecutionOnEngineJob < ApplicationJob
  queue_as :maintenance

  # Delegates starting a pending execution on the engine to the orchestrator,
  # which handles the per-table lock and re-enqueues on contention.
  # @param execution_history_id [Integer] the id of the execution to release.
  def perform(execution_history_id)
    MaintenanceOrchestrator.start_execution_on_engine(execution_history_id)
  end
end
