class IcebergTablesController < ApplicationController
  before_action :require_admin!, only: %i[run_maintenance]

  # Global view: every table of every catalog, with filters. With 100+
  # tables, browsing catalog by catalog does not scale.
  def index
    @catalogs   = Catalog.order(:name)
    @namespaces = IcebergTable.distinct.order(:namespace).pluck(:namespace)

    @tables = IcebergTable.includes(:catalog)
                          .left_joins(:maintenance_schedules)
                          .select("iceberg_tables.*, COUNT(maintenance_schedules.id) AS schedules_count")
                          .group("iceberg_tables.id")

    @tables = @tables.where(catalog_id: params[:catalog_id])       if params[:catalog_id].present?
    @tables = @tables.where(namespace: params[:namespace])         if params[:namespace].present?
    @tables = @tables.where(health_status: params[:health_status]) if params[:health_status].present?

    if params[:q].present?
      term = "%#{params[:q].downcase}%"
      @tables = @tables.where("LOWER(iceberg_tables.name) LIKE :t OR LOWER(iceberg_tables.namespace) LIKE :t", t: term)
    end

    @tables = @tables.order(Arel.sql("health_score ASC NULLS LAST"), :namespace, :name)
  end

  def show
    @table = IcebergTable.find(params[:id])
    @schedules = @table.maintenance_schedules.order(:operation)
    @executions = @table.execution_histories.latest.limit(20)
  end

  # Fallback for the table-level "run now": runs the table's plan.
  def run_maintenance
    @table = IcebergTable.find(params[:id])
    plan = @table.maintenance_plan

    if plan && !plan.is_paused
      MaintenanceOrchestrator.run_plan(plan.id)
      redirect_to @table, notice: "Maintenance enqueued."
    else
      redirect_to @table, alert: "This table has no active plan to run."
    end
  end
end
