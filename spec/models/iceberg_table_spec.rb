require "rails_helper"

RSpec.describe IcebergTable, type: :model do
  describe "active scopes" do
    it "separates active from inactive tables" do
      active = create(:iceberg_table)
      inactive = create(:iceberg_table)
      inactive.deactivate!

      expect(described_class.active).to contain_exactly(active)
      expect(described_class.inactive).to contain_exactly(inactive)
    end
  end

  describe "#deactivate!" do
    it "marks the table inactive and stamps the time" do
      table = create(:iceberg_table)
      now = Time.current

      table.deactivate!(at: now)

      expect(table).not_to be_active
      expect(table.deactivated_at).to be_within(1.second).of(now)
      expect(table).to be_persisted
    end
  end

  describe "name uniqueness" do
    it "allows an active and an inactive table with the same name" do
      catalog = create(:catalog)
      old = create(:iceberg_table, catalog:, namespace: "bronze", name: "t")
      old.deactivate!

      new = build(:iceberg_table, catalog:, namespace: "bronze", name: "t")

      expect(new).to be_valid
    end

    it "rejects two active tables with the same name" do
      catalog = create(:catalog)
      create(:iceberg_table, catalog:, namespace: "bronze", name: "t")

      expect(build(:iceberg_table, catalog:, namespace: "bronze", name: "t")).not_to be_valid
    end
  end

  describe "table_uuid uniqueness" do
    it "rejects two tables with the same uuid in the same catalog" do
      catalog = create(:catalog)
      create(:iceberg_table, catalog:, table_uuid: "uuid-1")

      expect(build(:iceberg_table, catalog:, table_uuid: "uuid-1")).not_to be_valid
    end

    it "allows the same uuid in different catalogs" do
      create(:iceberg_table, table_uuid: "uuid-1")

      expect(build(:iceberg_table, table_uuid: "uuid-1")).to be_valid
    end

    it "allows nil uuids" do
      expect(build(:iceberg_table, table_uuid: nil)).to be_valid
    end
  end

  describe "#metadata_snapshot" do
    it "returns a hash of key metadata fields" do
      table = create(:iceberg_table,
        total_records: 1000, total_data_files: 50, total_size_bytes: 5_000_000,
        position_deletes: 10, equality_deletes: 2,
        snapshot_count: 5, oldest_snapshot_at: 1.day.ago)

      snapshot = table.metadata_snapshot

      expect(snapshot).to include(
        "total_records" => 1000,
        "total_data_files" => 50,
        "total_size_bytes" => 5_000_000,
        "position_deletes" => 10,
        "equality_deletes" => 2,
        "snapshot_count" => 5
      )
      expect(snapshot["oldest_snapshot_at"]).to be_present
    end

    it "returns nil values when fields are blank" do
      table = create(:iceberg_table)

      snapshot = table.metadata_snapshot

      expect(snapshot["total_records"]).to be_nil
      expect(snapshot["total_data_files"]).to be_nil
    end
  end

  describe "#trino_identifier" do
    it "returns a three-part quoted identifier" do
      catalog = create(:catalog, name: "my_catalog")
      table = create(:iceberg_table, catalog:, namespace: "silver", name: "orders")

      expect(table.trino_identifier).to eq('"my_catalog"."silver"."orders"')
    end

    it "keeps dotted namespaces in a single quoted part" do
      catalog = create(:catalog, name: "cat")
      table = create(:iceberg_table, catalog:, namespace: "ns1.ns2.ns3", name: "t")

      expect(table.trino_identifier).to eq('"cat"."ns1.ns2.ns3"."t"')
    end
  end

  describe "#trino_metadata_table" do
    it "places the suffix inside the table quotes" do
      catalog = create(:catalog, name: "my_catalog")
      table = create(:iceberg_table, catalog:, namespace: "silver", name: "order_changes")

      expect(table.trino_metadata_table("files")).to eq('"my_catalog"."silver"."order_changes$files"')
    end

    it "works with manifests suffix" do
      catalog = create(:catalog, name: "cat")
      table = create(:iceberg_table, catalog:, namespace: "bronze", name: "users")

      expect(table.trino_metadata_table("manifests")).to eq('"cat"."bronze"."users$manifests"')
    end

    it "escapes double quotes in table name" do
      catalog = create(:catalog, name: "cat")
      table = create(:iceberg_table, catalog:, namespace: "ns", name: 'weird"name')

      expect(table.trino_metadata_table("files")).to eq('"cat"."ns"."weird""name$files"')
    end
  end
end
