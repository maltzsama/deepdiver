require "test_helper"

class CatalogSyncServiceTest < ActiveSupport::TestCase
  class FakeCatalogClient
    def namespaces
      [ "reporting" ]
    end

    def tables_in(namespace)
      [ "dwd_orders" ]
    end

    def table_metadata(namespace, table)
      { "metadata" => {
        "current-snapshot_id" => 1,
        "snapshots" => [ { "snapshot-id" => 1, "timestamp-ms" => (3.days.ago.to_f * 1000).to_i } ]
      } }
    end
  end

  test "materialises tables with health signals from the catalog" do
    catalog = build_catalog

    CatalogSyncService.new(catalog, client: FakeCatalogClient.new).sync

    table = catalog.iceberg_tables.find_by(namespace: "reporting", name: "dwd_orders")
    assert table
    assert_equal "healthy", table.health_status
    assert_equal 100, table.health_score
    assert_in_delta 3.days.ago.to_i, table.last_data_update.to_i, 5
  end

  test "re-running the sync is idempotent" do
    catalog = build_catalog

    2.times { CatalogSyncService.new(catalog, client: FakeCatalogClient.new).sync }

    assert_equal 1, catalog.iceberg_tables.count
  end

  class FlakyCatalogClient < FakeCatalogClient
    def tables_in(namespace)
      [ "good", "bad" ]
    end

    def table_metadata(namespace, table)
      raise "exploded" if table == "bad"

      super
    end
  end

  test "one broken table does not abort the whole sync" do
    catalog = build_catalog

    result = CatalogSyncService.new(catalog, client: FlakyCatalogClient.new).sync

    assert_equal 1, result[:errors].size
    assert_match(/bad: exploded/, result[:errors].first)
    assert catalog.iceberg_tables.exists?(namespace: "reporting", name: "good")
    assert_not catalog.iceberg_tables.exists?(namespace: "reporting", name: "bad")
  end

  class BrokenNamespaceClient < FakeCatalogClient
    def tables_in(namespace)
      raise "catalog unavailable"
    end
  end

  test "a broken namespace is reported and the sync continues" do
    catalog = build_catalog

    result = CatalogSyncService.new(catalog, client: BrokenNamespaceClient.new).sync

    assert_equal 1, result[:errors].size
    assert_match(/namespace reporting: catalog unavailable/, result[:errors].first)
  end
end
