# Tables that need attention: the ones whose health is degraded. One row per
# table, most recently degraded first.
class TriageQuery
  BAD_HEALTH = %w[critical].freeze

  Row = Struct.new(:table, :degraded_at, :reasons, keyword_init: true)

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

  # Selects the tables whose health is in a bad state, eager-loading their
  # catalog and maintenance plan.
  #
  # @return [ActiveRecord::Relation<IcebergTable>] the degraded tables.
  def candidates
    IcebergTable
      .active
      .includes(:catalog, :maintenance_plan)
      .where(health_status: BAD_HEALTH)
  end

  # Assembles a Row for a degraded table.
  # @param table [IcebergTable] the table to build a row for.
  # @return [TriageQuery::Row] the triage row for the table.
  def build_row(table)
    Row.new(table:, reasons: [ :health ], degraded_at: table.health_status_changed_at)
  end
end
