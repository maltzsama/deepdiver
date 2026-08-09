class TrinoManagerJob < ApplicationJob
  queue_as :maintenance

  # Step "start": guarantees only one maintenance runs at a time. A database
  # constraint violation means another execution holds the Trino lock, so we
  # back off instead of parking the thread.
  def perform(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)
    execution.update!(status: :running, current_step: :start)

    if TrinoLock.acquire(execution.id)
      MaintenanceOrchestrator.scale_up(execution.id)
    else
      MaintenanceOrchestrator.retry_lock_acquisition(execution.id)
    end
  end
end
