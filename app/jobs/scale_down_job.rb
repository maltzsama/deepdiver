class ScaleDownJob < ApplicationJob
  queue_as :maintenance

  # Final step: always daemon the Trino engine off and free the lock so the
  # next maintenance can start. Idempotent so duplicate enqueues are harmless.
  def perform(execution_history_id)
    execution = ExecutionHistory.find_by(id: execution_history_id)
    return if execution.nil?

    begin
      TrinoRuntime.ensure_stopped
      TrinoLock.release(execution_history_id: execution.id)
      execution.update!(current_step: :done)
    rescue StandardError => e
      # Do not overwrite a success: the maintenance itself worked. Only record
      # the teardown problem.
      message = "scale down failed: #{e.message}"
      if execution.status == "success"
        execution.update!(error_message: message)
        Rails.logger.error("Scale down failed after successful execution #{execution.id}: #{e.message}")
      else
        execution.update!(status: :failed, error_message: message)
      end
      raise
    end
  end
end
