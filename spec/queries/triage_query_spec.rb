require "rails_helper"

RSpec.describe TriageQuery do
  let(:catalog) { create(:catalog) }

  it "includes a table in critical health" do
    table = create(:iceberg_table, catalog:, health_status: "critical",
                                   health_score: 22, health_status_changed_at: 1.hour.ago)

    expect(described_class.new.call.map(&:table)).to include(table)
  end

  it "does not include a healthy table" do
    create(:iceberg_table, catalog:, health_status: "healthy", health_score: 95)

    expect(described_class.new.call).to be_empty
  end

  it "orders most recently degraded first" do
    old = create(:iceberg_table, catalog:, health_status: "critical",
                                 health_score: 10, health_status_changed_at: 3.days.ago)
    new = create(:iceberg_table, catalog:, health_status: "critical",
                                 health_score: 40, health_status_changed_at: 5.minutes.ago)

    expect(described_class.new.call.map(&:table)).to eq([ new, old ])
  end

  it "pushes tables without a known instant to the end" do
    unknown = create(:iceberg_table, catalog:, health_status: "critical",
                                     health_score: 5, health_status_changed_at: nil)
    known   = create(:iceberg_table, catalog:, health_status: "critical",
                                     health_score: 60, health_status_changed_at: 2.days.ago)

    expect(described_class.new.call.map(&:table)).to eq([ known, unknown ])
  end

  it "respects the limit" do
    create_list(:iceberg_table, 3, catalog:, health_status: "critical",
                                    health_score: 10, health_status_changed_at: 1.hour.ago)

    expect(described_class.new.call(limit: 2).size).to eq(2)
  end
end
