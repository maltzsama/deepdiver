class DashboardController < ApplicationController
  def index
    @worst_health_tables = IcebergTable.includes(:catalog)
                                       .order(Arel.sql("health_score ASC NULLS LAST"))
                                       .limit(10)
    @paused_schedules = MaintenanceSchedule.includes(:iceberg_table).where(is_paused: true)
  end
end
