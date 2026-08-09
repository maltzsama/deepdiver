class ScaleDownJob < ApplicationJob
  queue_as :maintenance

  # Final step: always daemon the Trino engine off and free the lock so the
  # next maintenance can start. Idempotent so duplicate enqueues are harmless.
  def perform(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)

    TrinoRuntime.ensure_stopped
    TrinoLock.release(execution_history_id: execution.id)
    execution.update!(current_step: :done)
  rescue StandardError => e
    execution.update!(status: :failed, error_message: "scale down failed: #{e.message}")
    raise
  end
end
