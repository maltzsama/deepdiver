require "rails_helper"

RSpec.describe TriageQuery do
  let(:catalog) { create(:catalog) }

  it "inclui tabela com saúde crítica" do
    table = create(:iceberg_table, catalog:, health_status: "critical",
                                   health_score: 22, health_status_changed_at: 1.hour.ago)

    expect(described_class.new.call.map(&:table)).to include(table)
  end

  it "inclui tabela fora do SLA mesmo com saúde ok" do
    table = create(:iceberg_table, catalog:, health_status: "healthy", health_score: 95)
    create(:table_freshness_sla, iceberg_table: table, enabled: true,
                                 status: "late", breached_since: 2.hours.ago)

    row = described_class.new.call.find { |r| r.table == table }

    expect(row).to be_present
    expect(row.reasons).to eq([ :freshness ])
  end

  it "NÃO inclui tabela saudável nas duas dimensões" do
    table = create(:iceberg_table, catalog:, health_status: "healthy", health_score: 95)
    create(:table_freshness_sla, iceberg_table: table, enabled: true, status: "ok")

    expect(described_class.new.call.map(&:table)).not_to include(table)
  end

  it "marca as duas razões quando ambas estão ruins" do
    table = create(:iceberg_table, catalog:, health_status: "critical",
                                   health_score: 15, health_status_changed_at: 3.hours.ago)
    create(:table_freshness_sla, iceberg_table: table, enabled: true,
                                 status: "late", breached_since: 30.minutes.ago)

    row = described_class.new.call.first

    expect(row.reasons).to contain_exactly(:health, :freshness)
    # Vale o instante mais recente: a novidade e o atraso, nao a saude.
    expect(row.degraded_at).to be_within(1.minute).of(30.minutes.ago)
  end

  it "ordena por degradação mais recente primeiro" do
    antiga = create(:iceberg_table, catalog:, health_status: "critical",
                                    health_score: 10, health_status_changed_at: 3.days.ago)
    nova   = create(:iceberg_table, catalog:, health_status: "critical",
                                    health_score: 40, health_status_changed_at: 5.minutes.ago)

    expect(described_class.new.call.map(&:table)).to eq([ nova, antiga ])
  end

  it "joga para o fim quem não tem instante conhecido" do
    sem_instante = create(:iceberg_table, catalog:, health_status: "critical",
                                          health_score: 5, health_status_changed_at: nil)
    com_instante = create(:iceberg_table, catalog:, health_status: "critical",
                                          health_score: 60, health_status_changed_at: 2.days.ago)

    expect(described_class.new.call.map(&:table)).to eq([ com_instante, sem_instante ])
  end

  it "ignora SLA desabilitado" do
    table = create(:iceberg_table, catalog:, health_status: "healthy", health_score: 90)
    create(:table_freshness_sla, iceberg_table: table, enabled: false, status: "late")

    expect(described_class.new.call.map(&:table)).not_to include(table)
  end
end
