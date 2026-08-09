require "test_helper"

class IcebergTableTest < ActiveSupport::TestCase
  test "fully_qualified_name joins namespace and name" do
    table = build_table
    assert_equal "reporting.dwd_orders", table.fully_qualified_name
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
