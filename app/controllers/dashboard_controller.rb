class DashboardController < ApplicationController
  def index
    authorize :dashboard
    @triage = TriageQuery.new.call
    @paused_plans = MaintenancePlan.where(is_paused: true).includes(iceberg_table: :catalog)

    # Contadores do topo continuam — são resumo, não lista.
    @health_counts = IcebergTable.group(:health_status).count
    @total_tables  = @health_counts.values.sum
    @freshness_counts = TableFreshnessSla.enabled.group(:status).count
    @open_error_count = ErrorEvent.open.count

    # Without a sync there is no fresh data: the UI must say how old it is.
    @last_sync_at = IcebergTable.maximum(:metadata_synced_at)
  end
end
