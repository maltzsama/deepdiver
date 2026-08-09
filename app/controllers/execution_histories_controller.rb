# Global log of operations. The per-table history stays in iceberg_tables#show;
# this screen answers "what ran on the lake today".
class ExecutionHistoriesController < ApplicationController
  def index
    @catalogs = Catalog.order(:name)

    @executions = ExecutionHistory
                  .includes(maintenance_schedule: { iceberg_table: :catalog })
                  .latest

    if params[:catalog_id].present?
      @executions = @executions.joins(maintenance_schedule: :iceberg_table)
                               .where(iceberg_tables: { catalog_id: params[:catalog_id] })
    end

    if params[:operation].present?
      @executions = @executions.joins(:maintenance_schedule)
                               .where(maintenance_schedules: { operation: params[:operation] })
    end

    @executions = @executions.where(status: params[:status]) if params[:status].present?

    @executions = @executions.limit(200)
  end
end
