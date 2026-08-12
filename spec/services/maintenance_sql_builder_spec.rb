require "rails_helper"

RSpec.describe MaintenanceSqlBuilder do
  let(:catalog) { create(:catalog, name: "analytics") }
  let(:table) { create(:iceberg_table, catalog: catalog, namespace: "reporting", name: "dwd_orders") }
  let(:plan) { create(:maintenance_plan, iceberg_table: table) }

  def built_sql(operation, config = {})
    step = plan.maintenance_steps.create!(operation: operation,
                                          position: MaintenancePlan::CANONICAL_ORDER.index(operation),
                                          config: config)
    described_class.build(table, step)
  end

  it "emits a 3-part quoted identifier for optimize with the default threshold" do
    expect(built_sql("optimize")).to eq(
      "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE optimize(file_size_threshold => '128MB')"
    )
  end

  it "emits a 3-part quoted identifier for optimize with a custom threshold" do
    expect(built_sql("optimize", { "file_size_threshold" => "256MB" })).to eq(
      "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE optimize(file_size_threshold => '256MB')"
    )
  end

  it "appends the WHERE clause to optimize when the operator set one" do
    expect(built_sql("optimize", { "where" => "event_hour >= current_timestamp() - INTERVAL 2 HOUR" })).to eq(
      "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE optimize(file_size_threshold => '128MB') " \
      "WHERE event_hour >= current_timestamp() - INTERVAL 2 HOUR"
    )
  end

  it "keeps the default threshold when only where is set on optimize" do
    expect(built_sql("optimize", { "where" => "event_date >= date '2024-01-01'" })).to eq(
      "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE optimize(file_size_threshold => '128MB') " \
      "WHERE event_date >= date '2024-01-01'"
    )
  end

  it "emits snapshot_ids on expire_snapshots when the operator set them" do
    expect(built_sql("expire_snapshots", { "snapshot_ids" => "123, 456" })).to eq(
      "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE " \
      "expire_snapshots(retention_threshold => '7d', snapshot_ids => ARRAY[123, 456])"
    )
  end

  it "emits a 3-part quoted identifier for expire_snapshots" do
    expect(built_sql("expire_snapshots")).to eq(
      "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE expire_snapshots(retention_threshold => '7d')"
    )
  end

  it "emits a 3-part quoted identifier for remove_orphan_files" do
    expect(built_sql("remove_orphan_files", { "retention_threshold" => "14d" })).to eq(
      "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE remove_orphan_files(retention_threshold => '14d')"
    )
  end

  it "emits a 3-part quoted identifier for optimize_manifests with no arguments" do
    expect(built_sql("optimize_manifests")).to eq(
      "ALTER TABLE \"analytics\".\"reporting\".\"dwd_orders\" EXECUTE optimize_manifests"
    )
  end
end
