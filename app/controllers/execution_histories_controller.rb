# Global log of operations. The per-table history stays in iceberg_tables#show;
# this screen answers "what ran on the lake today", chain-aware: each row is an
# execution with its nested steps.
class ExecutionHistoriesController < ApplicationController
  before_action :set_execution, only: %i[cancel]

  def index
    authorize ExecutionHistory
    @catalogs = Catalog.order(:name)

    @executions = ExecutionHistory
                  .includes(iceberg_table: :catalog, execution_steps: :maintenance_step)
                  .latest

    if params[:catalog_id].present?
      @executions = @executions.joins(:iceberg_table)
                               .where(iceberg_tables: { catalog_id: params[:catalog_id] })
    end

    if params[:operation].present?
      @executions = @executions.joins(:execution_steps)
                               .where(execution_steps: { operation: params[:operation] })
                               .distinct
    end

    if params[:stopped_at_step].present?
      @executions = @executions.joins(:execution_steps)
                               .where(execution_steps: { operation: params[:stopped_at_step], status: "failed" })
                               .distinct
    end

    @executions = @executions.where(status: params[:status]) if params[:status].present?

    @executions = @executions.limit(200)
  end

  # Operator cancellation of a running execution: mark it failed, free the
  # table lock and let the supervisor decide about the engine.
  def cancel
    authorize @execution, :cancel?
    @execution.update!(status: :failed, error_message: "cancelled by operator", finished_at: Time.current)
    TableLock.release(@execution)
    TrinoEngineSupervisor.demand_finished!
    redirect_to activity_path, notice: "Execution cancelled."
  end

  private

  def set_execution
    @execution = ExecutionHistory.find(params[:id])
  end
end
