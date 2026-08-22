# Global log of operations. The per-table history stays in iceberg_tables#show;
# this screen answers "what ran on the lake today". Maintenance and freshness
# are separate tabs with separate schemas - never interleaved, each paginated
# on its own source (the old merge of two limit(200) dropped the tail).
class ExecutionHistoriesController < ApplicationController
  before_action :set_execution, only: %i[cancel]

  TABS = %w[maintenance freshness].freeze

  # Lists executions as one block per run (timeline bar + legend) for the
  # maintenance tab, or a simple scan list for the freshness tab.
  def index
    authorize ExecutionHistory
    @catalogs = Catalog.order(:name)
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "maintenance"

    if @tab == "freshness"
      @pagy, @checks = pagy(freshness_scope, limit: 50)
    else
      @pagy, @executions = pagy(maintenance_scope, limit: 50)
    end
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
    redirect_to activity_path, notice: t("activity.notices.cancelled")
  end

  private

  # Loads the execution for the current request.
  def set_execution
    @execution = ExecutionHistory.find(params[:id])
  end

  # Maintenance executions with catalog/status/operation/stopped-at filters.
  def maintenance_scope
    scope = ExecutionHistory.includes(iceberg_table: :catalog, execution_steps: :maintenance_step)
    scope = scope.joins(:iceberg_table).where(iceberg_tables: { catalog_id: params[:catalog_id] }) if params[:catalog_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    if params[:operation].present?
      scope = scope.where(id: ExecutionHistory.joins(:execution_steps)
                        .where(execution_steps: { operation: params[:operation] }).select(:id))
    end
    if params[:stopped_at_step].present?
      scope = scope.where(id: ExecutionHistory.joins(:execution_steps)
                        .where(execution_steps: { operation: params[:stopped_at_step], status: "failed" }).select(:id))
    end

    scope.latest
  end

  # Freshness scans with catalog filter; the status filter speaks maintenance,
  # so map it onto the closest freshness meaning.
  def freshness_scope
    scope = FreshnessCheck.includes(iceberg_table: :catalog)
    scope = scope.joins(:iceberg_table).where(iceberg_tables: { catalog_id: params[:catalog_id] }) if params[:catalog_id].present?
    scope = scope.where(status: freshness_status_filter) if params[:status].present?

    scope.latest
  end

  # Maps maintenance statuses onto freshness ones ("failed"->"error").
  def freshness_status_filter
    { "failed" => "error", "success" => "ok" }.fetch(params[:status], params[:status])
  end
end
