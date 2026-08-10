class DashboardController < ApplicationController
  def index
    authorize :dashboard
    @health_counts = IcebergTable.group(:health_status).count
    @total_tables  = @health_counts.values.sum

    @worst_health_tables = IcebergTable.includes(:catalog)
                                       .where.not(health_score: nil)
                                       .order(Arel.sql("health_score ASC"))
                                       .limit(10)

    @paused_schedules = MaintenanceSchedule.includes(iceberg_table: :catalog)
                                           .where(is_paused: true)

    @recent_executions = ExecutionHistory
                         .includes(maintenance_schedule: :iceberg_table)
                         .latest
                         .limit(8)

    # Without a sync there is no fresh data: the UI must say how old it is.
    @last_sync_at = IcebergTable.maximum(:updated_at)
  end
end
