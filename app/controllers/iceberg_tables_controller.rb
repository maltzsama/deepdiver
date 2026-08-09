class IcebergTablesController < ApplicationController
  before_action :require_admin!, only: %i[run_maintenance]

  def show
    @table = IcebergTable.find(params[:id])
    @schedules = @table.maintenance_schedules.order(:operation)
    @executions = @table.execution_histories.latest.limit(20)
  end

  # Fallback for the table-level "run now": uses the first active schedule.
  def run_maintenance
    @table = IcebergTable.find(params[:id])
    schedule = @table.maintenance_schedules.dispatchable.first

    if schedule
      MaintenanceOrchestrator.run_schedule(schedule.id)
      redirect_to @table, notice: "Maintenance enqueued."
    else
      redirect_to @table, alert: "This table has no active schedule to run."
    end
  end
end
