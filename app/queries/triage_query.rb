# Tabelas que exigem acao, em UMA lista. Uma linha por tabela, com as duas
# dimensoes como colunas.
#
# Ordenacao: por quando entrou no estado ruim, MAIS RECENTE PRIMEIRO. Numa
# tela de triagem, o que esta vermelho ha dias ja foi visto; o que quebrou
# agora e a informacao nova.
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

    # NULL vai para o fim: sem instante conhecido, nao e novidade.
    rows.sort_by { |row| [ row.degraded_at.nil? ? 1 : 0, -(row.degraded_at&.to_i || 0) ] }
        .first(limit)
  end

  private

  # Selects the distinct tables whose health or enabled freshness SLA is in a
  # bad state, eager-loading their catalog, SLA, and maintenance plan.
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
      .distinct
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

    # Tabela ruim nas duas dimensoes: vale o instante MAIS RECENTE, porque
    # a novidade e o que acabou de acontecer.
    Row.new(table:, sla:, reasons:, degraded_at: instants.compact.max)
  end
end
