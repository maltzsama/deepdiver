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
      event.resolve!

      described_class.record(catalog: catalog, schema: "s", operation: "op",
                             source_system: "catalog", message: "boom")

      expect(event.reload.status).to eq("open")
      expect(event.resolved_at).to be_nil
    end
  end

  describe "#assign_to!" do
    it "keeps the status open and records who assigned" do
      admin = create(:user, :admin)
      operator = create(:user, :operator)
      event = described_class.create!(schema: "s", operation: "op", source_system: "catalog", message: "m", first_seen_at: Time.current, last_seen_at: Time.current)

      event.assign_to!(operator, by: admin)

      expect(event.reload.status).to eq("open")
      expect(event.assigned_to).to eq(operator)
      expect(event.assigned_by).to eq(admin)
    end

    it "notifies every responder when the target is a team" do
      team = create(:team)
      team.members << create(:user, :admin) << create(:user, :operator)
      event = described_class.create!(schema: "s", operation: "op", source_system: "catalog", message: "m", first_seen_at: Time.current, last_seen_at: Time.current)

      notified = event.assign_to!(team, by: create(:user, :admin))

      expect(notified.size).to eq(2)
      expect(event.assigned_to).to be_nil
      expect(event.context["assigned_team"]).to eq(team.name)
    end
  end

  describe "#acknowledge!" do
    it "moves an open event to acknowledged" do
      operator = create(:user, :operator)
      event = described_class.create!(schema: "s", operation: "op", source_system: "catalog", message: "m", first_seen_at: Time.current, last_seen_at: Time.current)

      event.acknowledge!(user: operator)

      expect(event.status).to eq("acknowledged")
      expect(event.acknowledged_at).to be_present
      expect(event.assigned_to).to eq(operator)
    end
  end

  describe "#resolve!" do
    it "closes the event" do
      event = described_class.create!(schema: "s", operation: "op", source_system: "catalog", message: "m", first_seen_at: Time.current, last_seen_at: Time.current)
      event.resolve!
      expect(event).to be_resolved
      expect(event.resolved_at).to be_present
    end
  end

  describe ".resolve_freshness!" do
    it "auto-resolves open freshness events of the recovered table only" do
      table = create(:iceberg_table)
      fresh = described_class.record_freshness_late!(table: table)
      other = described_class.record_freshness_late!(table: create(:iceberg_table))
      plain = described_class.create!(schema: "x", operation: "sync-table", source_system: "catalog", message: "m", first_seen_at: Time.current, last_seen_at: Time.current)

      described_class.resolve_freshness!(table: table)

      expect(fresh.reload.status).to eq("resolved")
      expect(fresh.resolved_at).to be_present
      expect(other.reload.status).to eq("open")
      expect(plain.reload.status).to eq("open")
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
