require "rails_helper"

RSpec.describe TrinoEngineConfig, "retention floors" do
  subject(:config) { described_class.instance }

  it "defaults both floors to the Trino default of 7d" do
    expect(config.expire_snapshots_min_retention).to eq("7d")
    expect(config.remove_orphan_files_min_retention).to eq("7d")
  end

  it "rejects a value that is not a magnitude plus a time unit" do
    config.expire_snapshots_min_retention = "soon"
    expect(config).not_to be_valid
    expect(config.errors[:expire_snapshots_min_retention].join).to match(/time unit/)
  end

  it "rejects a well-formed size that is not a duration" do
    config.remove_orphan_files_min_retention = "128MB"
    expect(config).not_to be_valid
  end

  it "accepts other time units" do
    config.expire_snapshots_min_retention = "12h"
    expect(config).to be_valid
  end

  it "maps the floors onto the Iceberg connector property names" do
    config.update!(expire_snapshots_min_retention: "2d", remove_orphan_files_min_retention: "3d")

    expect(config.connector_retention_properties).to eq(
      "iceberg.expire-snapshots.min-retention" => "2d",
      "iceberg.remove-orphan-files.min-retention" => "3d"
    )
  end

  it "reports the floor in seconds per operation" do
    config.update!(expire_snapshots_min_retention: "2d")

    expect(config.retention_floor_seconds("expire_snapshots")).to eq(172_800.0)
    expect(config.retention_floor_seconds("optimize")).to be_nil
  end
end

RSpec.describe MaintenanceStep, "retention against the engine floor" do
  let(:plan) { create(:maintenance_plan, cron: "0 2 * * *") }

  before { TrinoEngineConfig.instance.update!(expire_snapshots_min_retention: "7d") }

  it "rejects a retention below the configured floor, naming the floor" do
    step = build(:maintenance_step, maintenance_plan: plan, operation: "expire_snapshots",
                                    position: 1, config: { "retention_threshold" => "2d" })

    expect(step).not_to be_valid
    expect(step.errors[:config].join).to include("7d")
    expect(step.errors[:config].join).to include("2d")
  end

  it "accepts a retention at or above the floor" do
    step = build(:maintenance_step, maintenance_plan: plan, operation: "expire_snapshots",
                                    position: 1, config: { "retention_threshold" => "7d" })

    expect(step).to be_valid
  end

  it "accepts a shorter retention once the floor is lowered" do
    TrinoEngineConfig.instance.update!(expire_snapshots_min_retention: "1d")
    step = build(:maintenance_step, maintenance_plan: plan, operation: "expire_snapshots",
                                    position: 1, config: { "retention_threshold" => "2d" })

    expect(step).to be_valid
  end

  it "does not constrain an operation that has no floor" do
    step = build(:maintenance_step, maintenance_plan: plan, operation: "optimize",
                                    position: 0, config: { "retention_threshold" => "1h" })

    expect(step).to be_valid
  end
end

RSpec.describe TrinoCatalogProjection, "retention floors in connector properties" do
  it "reads the floors from the engine config" do
    TrinoEngineConfig.instance.update!(expire_snapshots_min_retention: "2d",
                                       remove_orphan_files_min_retention: "3d")
    catalog = create(:catalog)

    props = described_class.new(cluster_name: "test").send(:connector_properties, catalog)

    expect(props["iceberg.expire-snapshots.min-retention"]).to eq("2d")
    expect(props["iceberg.remove-orphan-files.min-retention"]).to eq("3d")
  end

  it "still lets a per-catalog properties override win" do
    TrinoEngineConfig.instance.update!(expire_snapshots_min_retention: "7d")
    catalog = create(:catalog, properties: { "iceberg.expire-snapshots.min-retention" => "1d" })

    props = described_class.new(cluster_name: "test").send(:connector_properties, catalog)

    expect(props["iceberg.expire-snapshots.min-retention"]).to eq("1d")
  end
end
