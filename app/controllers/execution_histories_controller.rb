# Global log of operations. The per-table history stays in iceberg_tables#show;
# this screen answers "what ran on the lake today", chain-aware: each row is an
# execution with its nested steps.
class ExecutionHistoriesController < ApplicationController
  before_action :set_execution, only: %i[cancel]

  # Lists the latest maintenance and freshness events interleaved into one
  # timeline, with catalog/status/operation filters.
  def index
    authorize ExecutionHistory
    @catalogs = Catalog.order(:name)

    # One timeline for both kinds of work the tool runs: maintenance
    # executions and freshness scans. The two sources are queried separately
    # (they share no columns worth a UNION) and interleaved by time here.
    @events = (Array(maintenance_events) + Array(freshness_events))
              .sort_by { |event| event[:at] }
              .reverse
              .first(200)
  end

  # Operator cancellation of an execution: mark it failed (running) or skipped
  # (pending, never ran), free the table lock and let the supervisor decide
  # about the engine.
  def cancel
    authorize @execution, :cancel?
    status = @execution.status == "pending" ? :skipped : :failed
    @execution.update!(status: status, error_message: "cancelled by operator", finished_at: Time.current)
    TableLock.release(@execution)
    TrinoEngineSupervisor.demand_finished!
    redirect_to activity_path, notice: "Execution cancelled."
  end

  private

  # Loads the execution for the current request.
  def set_execution
    @execution = ExecutionHistory.find(params[:id])
  end

  # Builds the maintenance side of the timeline, applying the catalog, status,
  # operation, and stopped-at-step filters.
  def maintenance_events
    return [] if params[:kind] == "freshness"

    scope = ExecutionHistory.includes(iceberg_table: :catalog, execution_steps: :maintenance_step)
    scope = scope.joins(:iceberg_table).where(iceberg_tables: { catalog_id: params[:catalog_id] }) if params[:catalog_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.joins(:execution_steps).where(execution_steps: { operation: params[:operation] }).distinct if params[:operation].present?
    if params[:stopped_at_step].present?
      scope = scope.joins(:execution_steps)
                   .where(execution_steps: { operation: params[:stopped_at_step], status: "failed" })
                   .distinct
    end

    scope.latest.limit(200).map do |execution|
      { kind: :maintenance, at: execution.started_at || execution.created_at,
        record: execution, table: execution.iceberg_table }
    end
  end

  # Builds the freshness-scan side of the timeline, applying the catalog and
  # status filters (via freshness_status_filter).
  def freshness_events
    return [] if params[:kind] == "maintenance"

    scope = FreshnessCheck.includes(iceberg_table: :catalog)
    scope = scope.joins(:iceberg_table).where(iceberg_tables: { catalog_id: params[:catalog_id] }) if params[:catalog_id].present?
    scope = scope.where(status: freshness_status_filter) if params[:status].present?

    scope.latest.limit(200).map do |check|
      { kind: :freshness, at: check.checked_at, record: check, table: check.iceberg_table }
    end
  end

  # The status filter speaks maintenance ("failed"/"success"); map it onto the
  # closest freshness meaning so filtering does not wipe one side of the feed.
  def freshness_status_filter
    { "failed" => "error", "success" => "ok" }.fetch(params[:status], params[:status])
  end
end
