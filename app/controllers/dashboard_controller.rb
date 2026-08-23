# Renders the landing overview: triage list, paused plans, health and
# freshness counters, and the age of the last metadata sync. Authorization is
# a simple Pundit check on the :dashboard policy.
class DashboardController < ApplicationController
  # Assembles the dashboard data: triage queries, paused plans, aggregate
  # health/freshness counts, open errors, and the last sync timestamp.
  def index
    authorize :dashboard
    @triage = TriageQuery.new.call
    @paused_plans = MaintenancePlan.where(is_paused: true).joins(:iceberg_table)
                                   .where(iceberg_tables: { active: true })
                                   .includes(iceberg_table: :catalog)

    # Contadores do topo continuam — são resumo, não lista.
    @health_counts = IcebergTable.active.group(:health_status).count
    @total_tables  = @health_counts.values.sum
    @freshness_counts = TableFreshnessSla.enabled.joins(:iceberg_table)
                                         .where(iceberg_tables: { active: true })
                                         .group(:status).count
    @open_error_count = ErrorEvent.open.count

    # Needs-action feed: the newest open/acknowledged errors, each row linking
    # straight to its detail page.
    @action_errors = ErrorEvent.where(status: %w[open acknowledged])
                               .order(last_seen_at: :desc).limit(5)

    # Without a sync there is no fresh data: the UI must say how old it is.
    @last_sync_at = IcebergTable.maximum(:metadata_synced_at)

    # The Trino cluster name, when one is known.
    @cluster_name = TrinoCluster.current_name
  end
end
