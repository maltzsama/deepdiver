require "test_helper"

class IcebergTableTest < ActiveSupport::TestCase
  test "fully_qualified_name is the three-part catalog.namespace.table identifier" do
    table = build_table
    assert_equal "analytics.reporting.dwd_orders", table.fully_qualified_name
  end

  test "fully_qualified_name omits the empty part for a table at the root" do
    catalog = build_catalog
    table = catalog.iceberg_tables.new(namespace: "", name: "rootbl")

    assert_equal "analytics.rootbl", table.fully_qualified_name
  end

  test "fully_qualified_name uses the Trino name override when set" do
    catalog = Catalog.new(name: "x", trino_catalog_name_override: "polaris_prod",
                          catalog_type: "polaris", endpoint: "http://x")
    table = IcebergTable.new(catalog: catalog, namespace: "silver", name: "orders")

    assert_equal "polaris_prod.silver.orders", table.fully_qualified_name
  end

  test "trino_identifier has three parts for a simple namespace" do
    table = build_table
    assert_equal "\"analytics\".\"reporting\".\"dwd_orders\"", table.trino_identifier
  end

  test "trino_identifier keeps a nested namespace as one quoted part" do
    catalog = Catalog.new(name: "x", trino_catalog_name_override: "polaris_prod", catalog_type: "polaris",
                          endpoint: "http://x")
    table = IcebergTable.new(catalog: catalog, namespace: "bronze.vendas.raw", name: "pedidos")

    identifier = table.trino_identifier
    assert_equal "\"polaris_prod\".\"bronze.vendas.raw\".\"pedidos\"", identifier
    assert_equal 3, identifier.scan(/"(?:[^"]|"")*"/).size
  end

  test "trino_identifier quotes unusual characters and escapes embedded quotes" do
    catalog = Catalog.new(name: "x", trino_catalog_name_override: "polaris_prod", catalog_type: "polaris",
                          endpoint: "http://x")
    table = IcebergTable.new(catalog: catalog, namespace: "ns-com-hifen", name: "Table \"Big\"")

    assert_equal "\"polaris_prod\".\"ns-com-hifen\".\"Table \"\"Big\"\"\"", table.trino_identifier
  end

  test "name is unique within the catalog namespace" do
    table = build_table
    duplicate = build_table.catalog.iceberg_tables.new(namespace: "reporting", name: "dwd_orders")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "health score must be bounded" do
    table = build_table
    table.health_score = 250
    assert_not table.valid?
  end
end
