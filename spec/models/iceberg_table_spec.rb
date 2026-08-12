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
end
