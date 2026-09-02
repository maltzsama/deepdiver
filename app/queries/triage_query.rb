# Tables that need attention, in ONE list. One row per table, with both
# dimensions as columns.
#
# Ordering: by when the table entered the bad state, MOST RECENT FIRST. On a
# triage screen, what has been red for days has already been seen; what just
# broke is the new information.
class TriageQuery
  BAD_HEALTH = %w[critical].freeze
  BAD_FRESHNESS = %w[late warning].freeze

  Row = Struct.new(:table, :sla, :degraded_at, :reasons, keyword_init: true)

  # Builds one row per degraded table, sorted by most recently degraded first
  # (tables that entered a bad state long ago are pushed to the end), then
  # truncates to the given limit.
  # @param limit [Integer] the maximum number of rows to return.
  # @return [Array<TriageQuery::Row>] the most recently degraded tables.
  def call(limit: 50)
    rows = candidates.map { |table| build_row(table) }

    # NULLs sort last: with no known instant, it is not new information.
    rows.sort_by { |row| [ row.degraded_at.nil? ? 1 : 0, -(row.degraded_at&.to_i || 0) ] }
        .first(limit)
  end

  private

  # Selects the tables whose health or enabled freshness SLA is in a bad
  # state, eager-loading their catalog, SLA, and maintenance plan.
  #
  # table_freshness_sla is has_one, so the left join never produces duplicate
  # rows and no DISTINCT is needed. DISTINCT on iceberg_tables.* would break on
  # Postgres anyway: the json columns have no equality operator.
  # @return [ActiveRecord::Relation<IcebergTable>] the degraded tables.
  def candidates
    IcebergTable
      .active
      .includes(:catalog, :table_freshness_sla, :maintenance_plan)
      .left_joins(:table_freshness_sla)
      .where(
        IcebergTable.arel_table[:health_status].in(BAD_HEALTH)
          .or(TableFreshnessSla.arel_table[:status].in(BAD_FRESHNESS)
              .and(TableFreshnessSla.arel_table[:enabled].eq(true)))
      )
  end

  # Assembles a Row for a table, collecting the reasons it is degraded and the
  # most recent instant it entered a bad state.
  # @param table [IcebergTable] the table to build a row for.
  # @return [TriageQuery::Row] the triage row for the table.
  def build_row(table)
    sla = table.table_freshness_sla
    reasons = []
    instants = []

    if BAD_HEALTH.include?(table.health_status)
      reasons << :health
      instants << table.health_status_changed_at
    end

    if sla&.enabled? && BAD_FRESHNESS.include?(sla.status)
      reasons << :freshness
      instants << (sla.breached_since || sla.status_changed_at)
    end

    # Bad on both dimensions: the MOST RECENT instant wins, because the new
    # information is whatever just happened.
    Row.new(table:, sla:, reasons:, degraded_at: instants.compact.max)
  end
end
