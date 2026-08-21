# Coordinates the maintenance lifecycle: materialises execution chains, pushes
# them through the job backend and hands the engine lifecycle to the supervisor.
module MaintenanceOrchestrator
  # Returns the job-queue backend implementation (Solid Queue by default).
  #
  # @return [MaintenanceOrchestrator::Backend] the backend
  def self.backend
    @backend ||= SolidQueueBackend.new
  end

  # Enqueue a new run of a maintenance plan. Materialises the chain NOW (what
  # will run and what stays out is visible before it starts, and the decision
  # does not change mid-chain), then hands the engine lifecycle over to the
  # supervisor.
  def self.run_plan(plan_id, at: Time.current)
    plan = MaintenancePlan.find(plan_id)

    # Idempotent: a table already queued or running does not queue again.
    # Without this, rapid "run now" clicks pile up N pending executions that
    # all resolve to "skipped" once the engine comes up.
    existing = plan.execution_histories.find_by(status: %w[pending running])
    return existing if existing

    # A leftover lock from a finished execution must never block a new run.
    TableLock.reap_stale!

    execution = plan.execution_histories.create!(status: :pending, current_step: :start,
                                                 iceberg_table_id: plan.iceberg_table_id,
                                                 started_at: at)

    plan.maintenance_steps.each do |step|
      running = step.enabled && step.due_at?(at)
      reason = running ? nil : skip_reason(step, at)

      execution.execution_steps.create!(
        maintenance_step: step,
        operation: step.operation,
        status: running ? "pending" : "skipped",
        skip_reason: reason
      )
    end

    # Nothing due: not worth bringing the engine up.
    if execution.execution_steps.where(status: "pending").none?
      execution.update!(status: :success, current_step: "done", finished_at: at)
      return execution
    end

    TrinoEngineSupervisor.demand_arrived!(
      dispatch: -> { start_execution_on_engine(execution.id) }
    )
    execution
  end

  # Why a step is skipped at a given time (disabled or outside its cadence).
  #
  # @param step [MaintenanceStep] the step to evaluate
  # @param at [Time] the reference time
  # @return [String, nil] the skip reason, or nil when due
  def self.skip_reason(step, at)
    return "step disabled" unless step.enabled
    return nil if step.due_at?(at)

    "outside cadence (#{step.cadence_cron})"
  end
  private_class_method :skip_reason

  # Enqueues a freshness sweep, unless there is nothing enabled - otherwise
  # the engine would come up 24 times a day to check nothing. Inactive tables
  # (dropped from their catalog) are skipped.
  def self.enqueue_freshness_sweep
    return nil if TableFreshnessSla.enabled.joins(:iceberg_table)
                                   .where(iceberg_tables: { active: true }).none?

    run = FreshnessRun.create!(status: "pending")
    TrinoEngineSupervisor.demand_arrived!(
      dispatch: -> { start_freshness_sweep(run.id) }
    )
    run
  end

  # Dispatches a freshness sweep onto the backend.
  #
  # @param freshness_run_id [Integer] the run to start
  def self.start_freshness_sweep(freshness_run_id)
    backend.start_freshness_sweep(freshness_run_id)
  end

  # Releases a pending execution onto the engine: acquires the per-table lock
  # and, when successful, enqueues the maintenance step. On lock contention the
  # dispatch is skipped and recorded - never queued (queueing would grow
  # forever on overlapping dispatches).
  def self.start_execution_on_engine(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)

    unless execution.status == "pending"
      Rails.logger.warn("start_execution_on_engine: execution #{execution.id} is #{execution.status}, not pending; skipping")
      return
    end

    execution.update!(status: :running, current_step: :start)

    if TableLock.acquire(execution)
      execute_maintenance(execution_history_id)
    else
      skip_for_overlap(execution)
    end
  end

  # Marks an execution skipped because its table lock is contended, and tells
  # the supervisor demand dropped - otherwise the engine would stay up forever
  # with nothing left to run.
  #
  # @param execution [ExecutionHistory] the execution to skip
  def self.skip_for_overlap(execution)
    execution.update!(
      status: :skipped,
      current_step: "start",
      finished_at: Time.current,
      error_message: "previous execution still running on this table"
    )
    TrinoEngineSupervisor.demand_finished!
  end
  private_class_method :skip_for_overlap

  # Enqueues a catalog sync through the backend.
  #
  # @param catalog_id [Integer] the catalog to sync
  # @param force [Boolean] whether to force a full resync
  def self.sync_catalog(catalog_id, force: false)
    backend.sync_catalog(catalog_id, force: force)
  end

  # Retries acquiring the table lock for an execution via the backend.
  #
  # @param execution_history_id [Integer] the execution to retry
  def self.retry_lock_acquisition(execution_history_id)
    backend.retry_lock_acquisition(execution_history_id)
  end

  # Asks the backend to supervise the engine start.
  def self.supervise_engine_start
    backend.supervise_engine_start
  end

  # Asks the backend to drain the engine.
  def self.drain_engine
    backend.drain_engine
  end

  # Dispatches the maintenance chain of an execution via the backend.
  #
  # @param execution_history_id [Integer] the execution to run
  def self.execute_maintenance(execution_history_id)
    backend.execute_maintenance(execution_history_id)
  end

  # Retries the maintenance of an execution via the backend.
  #
  # @param execution_history_id [Integer] the execution to retry
  def self.retry_maintenance(execution_history_id)
    backend.retry_maintenance(execution_history_id)
  end
end
