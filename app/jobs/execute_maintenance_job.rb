# Runs a single step of a maintenance execution and enqueues the next one,
# chaining through the materialised plan until every step has finished.
class ExecuteMaintenanceJob < ApplicationJob
  queue_as :maintenance

  MAX_RETRIES = 3
  RETRY_WAIT = 10.minutes

  # Runs ONE step and enqueues the next. The engine is NOT brought down between
  # steps - the TrinoEngineSupervisor owns that. The chain was materialised by
  # run_plan with each step's cadence already resolved; order is always
  # maintenance_steps.position.
  # @param execution_history_id [Integer] the id of the execution being worked through.
  def perform(execution_history_id)
    execution = ExecutionHistory.find(execution_history_id)

    unless execution.status == "running"
      retry_pending(execution, execution_history_id)
      return
    end

    if execution.metadata_before.nil?
      execution.update!(metadata_before: execution.iceberg_table.metadata_snapshot)
    end

    # retry_count on the execution counts pending-dispatch retries only (step
    # retries live on ExecutionStep). Once the dispatch is visible those are
    # spent, so clear the budget - otherwise a healthy execution kept rendering
    # as "retrying" for the rest of the chain.
    execution.update!(retry_count: 0) if execution.retry_count.positive?

    step = next_step_for(execution)

    return finish_chain(execution) if step.nil?

    run_step(execution, step)
  end

  private

  # A pending execution means start_execution_on_engine wrote status: :running
  # on the primary DB but the commit may not be visible yet (the enqueue happens
  # on a separate queue-DB connection before the primary transaction commits). A
  # worker that consumed the job in that window must retry shortly instead of
  # abandoning the execution - it would stay running with a NULL heartbeat and
  # be reaped as an orphan. Limited by retry_count so a genuinely stuck
  # execution does not loop forever.
  #
  # @param execution [ExecutionHistory] the execution whose job was consumed
  # @param execution_history_id [Integer] the execution id to re-enqueue
  def retry_pending(execution, execution_history_id)
    return unless execution.status == "pending"

    if execution.retry_count >= MAX_RETRIES
      # Do NOT just give up: "pending" counts as demand (TrinoDemand::
      # ACTIVE_EXECUTION_STATUSES), reap_orphans! only looks at "running", and
      # the watchdog only watches the engine row - so an abandoned pending
      # execution kept the engine up forever and permanently blocked its table
      # through run_plan's already-queued guard. Fail it explicitly instead.
      Rails.logger.error("ExecuteMaintenanceJob: execution #{execution.id} still pending after " \
                         "#{MAX_RETRIES} retries; failing it so demand drops")
      ExecutionFailureHandler.handle(
        execution,
        "dispatch never became visible after #{MAX_RETRIES} retries (primary commit lost?)"
      )
      TrinoEngineSupervisor.demand_finished!
      return
    end

    execution.increment!(:retry_count)
    Rails.logger.info("ExecuteMaintenanceJob: execution #{execution.id} still pending; retrying")
    MaintenanceOrchestrator.retry_pending_maintenance(execution_history_id)
  end

  # Finds the next pending step for the execution, ordered by the maintenance
  # plan's position.
  # @param execution [ExecutionHistory] the execution whose steps are inspected.
  # @return [ExecutionStep, nil] the next pending step, or nil when none remain.
  def next_step_for(execution)
    execution.execution_steps
             .joins(:maintenance_step)
             .where(status: "pending")
             .order("maintenance_steps.position ASC")
             .first
  end

  # Marks the step running, executes its SQL on Trino, records the result, and
  # enqueues the next step. Fails the step and notifies the supervisor on error,
  # retrying on commit conflicts.
  # @param execution [ExecutionHistory] the execution owning the step.
  # @param result_row [ExecutionStep] the step record to run.
  def run_step(execution, result_row)
    maintenance_step = result_row.maintenance_step
    result_row.update!(status: "running", started_at: Time.current)
    execution.update!(current_step: result_row.operation)

    metrics = execute_step(execution, maintenance_step, result_row)

    # Once the SQL succeeded on Trino, the step is succeeded. The post-success
    # bookkeeping below is best-effort: an infrastructure hiccup in a broadcast
    # or an enqueue must NOT rewrite a completed step to failed.
    result_row.update!(status: "succeeded", finished_at: Time.current,
                       metrics: metrics, trino_query_id: metrics["query_id"].presence || result_row.trino_query_id)
    maintenance_step&.update_column(:last_run_at, Time.current)
    complete_step_bookkeeping(execution)
  rescue TrinoRuntime::CommitConflict => e
    handle_commit_conflict(execution, result_row, e)
  rescue StandardError => e
    result_row&.update!(status: "failed", finished_at: Time.current, error_message: e.message)
    table = execution.iceberg_table
    context = "#{result_row.operation} on #{table.fully_qualified_name} (#{table.catalog&.name})"
    ExecutionFailureHandler.handle(execution, "#{context}: #{e.message}")
    # The handler marked the execution failed, so demand may have dropped to
    # zero - let the supervisor evaluate whether the engine can drain.
    TrinoEngineSupervisor.demand_finished!
  end

  # Post-success bookkeeping for a completed step: broadcasts the activity and
  # enqueues the next chain link. Best-effort — a failure here is logged, not
  # propagated, so a succeeded step is never rewritten to failed.
  #
  # @param execution [ExecutionHistory] the execution owning the step.
  def complete_step_bookkeeping(execution)
    ActivityBroadcaster.broadcast!
    MaintenanceOrchestrator.execute_maintenance(execution.id)
  rescue StandardError => e
    # The step already succeeded on Trino; the chain advance can be re-driven by
    # a later sweep. Log it rather than failing the whole execution.
    Rails.logger.warn("Post-success bookkeeping failed for execution #{execution.id}: #{e.message}")
  end

  # Executes the SQL for a step. OPTIMIZE on a many-partition table is split by
  # OptimizeStatementPlanner into one statement per bounded partition group so
  # no single query exceeds the connector's open-writers limit; every other
  # step runs its single statement.
  #
  # @param execution [ExecutionHistory] the execution owning the step
  # @param maintenance_step [MaintenanceStep] the step being run
  # @param result_row [ExecutionStep] the step record
  # @return [Hash] the aggregated metrics
  def execute_step(execution, maintenance_step, result_row)
    sqls = OptimizeStatementPlanner.new(execution.iceberg_table, maintenance_step).statements(execution_id: execution.id)

    return run_sql(sqls.first, execution, result_row) if sqls.size == 1

    aggregate_metrics(sqls.map do |sql|
      run_sql(sql, execution, result_row)
    end)
  end

  # Runs one SQL statement through the runtime and returns its metrics.
  #
  # @param sql [String] the statement
  # @param execution [ExecutionHistory] the execution for heartbeats
  # @param result_row [ExecutionStep] the step for query id/progress
  # @return [Hash] the metrics payload
  def run_sql(sql, execution, result_row)
    TrinoRuntime.execute(sql, execution_id: execution.id, execution: execution, step: result_row)
  end

  # Merges the metrics of multiple statements into one result, summing row
  # counts and keeping the last query id.
  #
  # @param metrics [Array<Hash>] the per-statement metrics
  # @return [Hash] the aggregated metrics
  def aggregate_metrics(metrics)
    {
      "rows" => metrics.sum { |m| m["rows"].to_i },
      "query_id" => metrics.map { |m| m["query_id"] }.compact.last,
      "batched_statements" => metrics.size
    }.compact
  end

  # Handles a Trino commit conflict on a step: fails it after the retry limit,
  # otherwise increments the retry counter and re-enqueues the execution.
  # @param execution [ExecutionHistory] the execution owning the step.
  # @param result_row [ExecutionStep] the step that hit the conflict.
  # @param error [TrinoRuntime::CommitConflict] the raised conflict error.
  def handle_commit_conflict(execution, result_row, error)
    if result_row.retry_count >= MAX_RETRIES
      result_row.update!(status: "failed", finished_at: Time.current,
                         error_message: "commit conflict after #{MAX_RETRIES} attempts")
      ExecutionFailureHandler.handle(execution, "commit conflict in #{result_row.operation}")
    else
      result_row.increment!(:retry_count)
      # The execution stays "running", so it keeps counting as demand: the
      # engine stays up on its own during the wait.
      MaintenanceOrchestrator.retry_maintenance(execution.id)
    end
  end

  # Marks the execution successful, resets the plan's failure counter, frees
  # the per-table lock, notifies the supervisor that demand has finished, and
  # refreshes the table's metadata so the UI reflects the post-maintenance state.
  # @param execution [ExecutionHistory] the execution that just completed.
  def finish_chain(execution)
    unless execution.status == "running"
      Rails.logger.warn("finish_chain: execution #{execution.id} is #{execution.status}, not running")
      return
    end

    execution.update!(status: :success, current_step: "done", finished_at: Time.current)
    execution.maintenance_plan&.update!(consecutive_failures: 0)
    TableLock.release(execution)

    # Metadata refresh and Trino enrichment run BEFORE demand_finished! — the
    # engine must still be up for the $files/$manifests queries. Draining first
    # would tear the engine down and the enrichment would fail (and be silently
    # swallowed), leaving size/manifest data unpopulated.
    table = execution.iceberg_table
    if table
      CatalogSyncService.sync_table(table.id)
      CatalogSyncService.enrich_from_trino!(table.reload)
      execution.update!(metadata_after: table.reload.metadata_snapshot)
      check_records_integrity!(execution)
    end

    TrinoEngineSupervisor.demand_finished!
  end

  # Compares total_records before and after maintenance. Only a decrease is
  # flagged as a violation — maintenance never removes logical rows, so a drop
  # means data was lost. An increase is a concurrent append (normal ingest
  # during the maintenance window) and is silently ignored.
  def check_records_integrity!(execution)
    before = execution.metadata_before&.dig("total_records")
    after  = execution.metadata_after&.dig("total_records")
    return if before.nil? || after.nil?
    return if after >= before

    table = execution.iceberg_table
    ErrorEvent.record(
      catalog: table.catalog, schema: table.namespace, table: table.name,
      operation: "records-integrity", source_system: "execution",
      severity: "error",
      error_class: "RecordsIntegrityViolation",
      message: "Maintenance on #{table.fully_qualified_name} decreased total_records " \
               "from #{before} to #{after} (delta: #{after - before})"
    )
  end
end
