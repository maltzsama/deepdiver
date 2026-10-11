# Global log of operations. The per-table history stays in iceberg_tables#show;
# this screen answers "what happened recently" — the maintenance executions.
class ExecutionHistoriesController < ApplicationController
  before_action :set_execution, only: %i[cancel]

  PAGE_SIZE = 50

  # Lists the timeline of executions, newest first.
  def index
    authorize ExecutionHistory
    @catalogs = Catalog.order(:name)
    filters = params.permit(:catalog_id, :table_id, :status, :operation, :stopped_at_step, :page)
    timeline = OperationTimeline.new(
      catalog_id: filters[:catalog_id].to_s.presence,
      table_id: filters[:table_id].to_s.presence,
      status: filters[:status].to_s.presence,
      operation: filters[:operation].to_s.presence,
      stopped_at_step: filters[:stopped_at_step].to_s.presence
    )

    @pagy, @rows = pagy(timeline.collection, limit: PAGE_SIZE)
    @rows = @rows.map(&:symbolize_keys)

    load_records(@rows)
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

  # Loads the executions referenced by the timeline rows, so the view renders
  # without N+1.
  #
  # @param rows [Array<Hash>] the timeline rows
  def load_records(rows)
    execution_ids = rows.filter_map { |r| r[:record_id] if r[:kind] == "maintenance" }

    @executions = ExecutionHistory.where(id: execution_ids)
                                  .includes(iceberg_table: :catalog, execution_steps: :maintenance_step)
                                  .index_by(&:id)
  end

  # Loads the execution for the current request.
  def set_execution
    @execution = ExecutionHistory.find(params[:id])
  end
end
