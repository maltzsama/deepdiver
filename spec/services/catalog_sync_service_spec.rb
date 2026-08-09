require "rails_helper"

RSpec.describe CatalogSyncService do
  class FlakyCatalogClient
    def namespaces
      [ "bronze" ]
    end

    def tables_in(_namespace)
      [ "good", "bad" ]
    end

    def table_metadata(_namespace, table)
      raise "exploded" if table == "bad"

      { "metadata" => { "current-snapshot_id" => 1, "snapshots" => [] } }
    end
  end

  it "keeps syncing when one table fails" do
    catalog = create(:catalog)

    result = CatalogSyncService.new(catalog, client: FlakyCatalogClient.new).sync

    expect(result[:errors].size).to eq(1)
    expect(result[:errors].first).to match(/bad: exploded/)
    expect(catalog.iceberg_tables.exists?(namespace: "bronze", name: "good")).to be true
    expect(catalog.iceberg_tables.exists?(namespace: "bronze", name: "bad")).to be false
  end
end
