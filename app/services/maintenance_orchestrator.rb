module MaintenanceOrchestrator
  def self.backend
    @backend ||= SolidQueueBackend.new
  end

  # Enqueue a new run of a maintenance plan. Materialises the chain NOW (what
  # will run and what stays out is visible before it starts, and the decision
  # does not change mid-chain), then hands the engine lifecycle over to the
  # supervisor.
  def self.run_plan(plan_id, at: Time.current)
    plan = MaintenancePlan.find(plan_id)

    execution = plan.execution_histories.create!(status: :pending, current_step: :start,
                                                 iceberg_table_id: plan.iceberg_table_id,
                                                 started_at: at)

    plan.maintenance_steps.each do |step|
      running = step.enabled && step.due_at?(at)

      execution.execution_steps.create!(
        maintenance_step: step,
        operation: step.operation,
        status: running ? "pending" : "skipped",
        error_message: skip_reason(step, at)
      )
    end

    # Nothing due: not worth bringing the engine up.
    if execution.execution_steps.where(status: "pending").none?
      execution.update!(status: :success, current_step: "done", finished_at: at)
      return execution
    end

    TrinoEngineSupervisor.on_execution_enqueued(execution)
    execution
  end

  def self.skip_reason(step, at)
    return "step disabled" unless step.enabled
    return nil if step.due_at?(at)

    "outside cadence (#{step.cadence_cron})"
  end
  private_class_method :skip_reason

  # Releases a pending execution onto the engine: acquires the per-table lock
  # and, when successful, enqueues the maintenance step. On lock contention the
  # dispatch is skipped and recorded - never queued (queueing would grow
  # forever on overlapping dispatches).
  def self.start_execution_on_engine(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)
    execution.update!(status: :running, current_step: :start)

    if TableLock.acquire(execution)
      execute_maintenance(execution_history_id)
    else
      skip_for_overlap(execution)
    end
  end

  def self.skip_for_overlap(execution)
    execution.update!(
      status: :skipped,
      current_step: "start",
      finished_at: Time.current,
      error_message: "previous execution still running on this table"
    )
  end
  private_class_method :skip_for_overlap

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
