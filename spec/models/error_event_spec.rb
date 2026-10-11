require "rails_helper"

RSpec.describe ErrorEvent, type: :model do
  describe ".record" do
    it "merges recurrences into one event with a growing count" do
      catalog = create(:catalog)
      2.times do
        described_class.record(catalog: catalog, schema: "reporting", table: "t",
                               operation: "sync-table", source_system: "catalog", message: "boom")
      end
      expect(described_class.count).to eq(1)
      expect(described_class.last.occurrence_count).to eq(2)
    end

    it "reopens a resolved event when the failure recurs" do
      catalog = create(:catalog)
      event = described_class.record(catalog: catalog, schema: "s", operation: "op",
                                     source_system: "catalog", message: "boom")
      event.update!(status: "resolved", resolved_at: Time.current)

      described_class.record(catalog: catalog, schema: "s", operation: "op",
                             source_system: "catalog", message: "boom")

      expect(event.reload.status).to eq("open")
      expect(event.resolved_at).to be_nil
    end
  end

  describe ".table_events" do
    it "isolates events to the table's own catalog" do
      catalog_a = create(:catalog)
      catalog_b = create(:catalog)
      table = create(:iceberg_table, catalog: catalog_a, namespace: "silver", name: "orders")

      described_class.record(catalog: catalog_a, schema: "silver", table: "orders",
                             operation: "sync-table", source_system: "catalog", message: "own failure")
      described_class.record(catalog: catalog_b, schema: "silver", table: "orders",
                             operation: "sync-table", source_system: "catalog", message: "other catalog")

      events = described_class.table_events(table)

      expect(events.count).to eq(1)
      expect(events.first.message).to eq("own failure")
    end
  end
end
