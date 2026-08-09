module MaintenanceOrchestrator
  def self.backend
    @backend ||= SolidQueueBackend.new
  end

  # Enqueue a new run of a maintenance plan. Creates the execution_history
  # record and hands the engine lifecycle over to the supervisor.
  def self.run_plan(plan_id)
    plan = MaintenancePlan.find(plan_id)
    execution = plan.execution_histories.create!(status: :pending, current_step: :start)
    TrinoEngineSupervisor.on_execution_enqueued(execution)
    execution
  end

  # Releases a pending execution onto the engine: acquires the per-table lock
  # and, when successful, enqueues the maintenance step.
  def self.start_execution_on_engine(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)
    execution.update!(status: :running, current_step: :start)

    if TableLock.acquire(execution)
      execute_maintenance(execution_history_id)
    else
      retry_lock_acquisition(execution_history_id)
    end
  end

  def self.sync_catalog(catalog_id, force: false)
    backend.sync_catalog(catalog_id, force: force)
  end

  def self.retry_lock_acquisition(execution_history_id)
    backend.retry_lock_acquisition(execution_history_id)
  end

  def self.supervise_engine_start
    backend.supervise_engine_start
  end

  def self.drain_engine
    backend.drain_engine
  end

  def self.execute_maintenance(execution_history_id)
    backend.execute_maintenance(execution_history_id)
  end

  def self.retry_maintenance(execution_history_id)
    backend.retry_maintenance(execution_history_id)
  end
end
