module MaintenanceOrchestrator
  def self.backend
    @backend ||= SolidQueueBackend.new
  end

  # Enqueue a new run of a maintenance schedule. Creates the execution_history
  # record and starts the state machine.
  def self.run_schedule(schedule_id)
    schedule = MaintenanceSchedule.find(schedule_id)
    execution = schedule.execution_histories.create!(status: :pending, current_step: :start)
    backend.start_execution(execution.id)
    execution
  end

  def self.sync_catalog(catalog_id, force: false)
    backend.sync_catalog(catalog_id, force: force)
  end

  def self.retry_lock_acquisition(execution_history_id)
    backend.retry_lock_acquisition(execution_history_id)
  end

  def self.scale_up(execution_history_id)
    backend.scale_up(execution_history_id)
  end

  def self.retry_scale_up(execution_history_id)
    backend.retry_scale_up(execution_history_id)
  end

  def self.execute_maintenance(execution_history_id)
    backend.execute_maintenance(execution_history_id)
  end

  def self.retry_maintenance(execution_history_id)
    backend.retry_maintenance(execution_history_id)
  end

  def self.scale_down(execution_history_id)
    backend.scale_down(execution_history_id)
  end
end
