require "test_helper"

class MaintenanceSqlBuilderTest < ActiveSupport::TestCase
  def assert_built(operation, expected, config = {})
    schedule = build_schedule(operation: operation, config: config)
    assert_equal expected, MaintenanceSqlBuilder.build(schedule)
  end

  test "optimize uses the default file size threshold" do
    assert_built "optimize",
                 "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE optimize(file_size_threshold => '128MB')"
  end

  test "optimize honors a custom file size threshold" do
    assert_built "optimize",
                 "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE optimize(file_size_threshold => '256MB')",
                 { "file_size_threshold" => "256MB" }
  end

  test "expire_snapshots uses the retention threshold" do
    assert_built "expire_snapshots",
                 "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE expire_snapshots(retention_threshold => '7d')"
  end

  test "remove_orphan_files uses the retention threshold" do
    assert_built "remove_orphan_files",
                 "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE remove_orphan_files(retention_threshold => '14d')",
                 { "retention_threshold" => "14d" }
  end

  test "optimize_manifests has no arguments" do
    assert_built "optimize_manifests",
                 "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE optimize_manifests"
  end
end
