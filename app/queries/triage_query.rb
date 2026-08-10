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

  def call(limit: 50)
    rows = candidates.map { |table| build_row(table) }

    # NULL vai para o fim: sem instante conhecido, nao e novidade.
    rows.sort_by { |row| [ row.degraded_at.nil? ? 1 : 0, -(row.degraded_at&.to_i || 0) ] }
        .first(limit)
  end

  private

  def candidates
    IcebergTable
      .includes(:catalog, :table_freshness_sla, :maintenance_plan)
      .left_joins(:table_freshness_sla)
      .where(
        IcebergTable.arel_table[:health_status].in(BAD_HEALTH)
          .or(TableFreshnessSla.arel_table[:status].in(BAD_FRESHNESS)
              .and(TableFreshnessSla.arel_table[:enabled].eq(true)))
      )
      .distinct
  end

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
