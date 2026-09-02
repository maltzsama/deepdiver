require "rails_helper"

RSpec.describe HealthHelper, type: :helper do
  # The rows are built from the evaluation alone - including the measured
  # values it emits under :details - so a persisted read and a fresh
  # evaluation render identically.
  let(:evaluation) do
    { score: 62, status: :warning, coverage: 90,
      components: { fragmentation: 0.58, snapshot_buildup: 0.81,
                    delete_overhead: 0.94, manifest_buildup: nil },
      details: { average_file_size: 74 * 1024 * 1024,
                 target_file_size: 128 * 1024 * 1024,
                 snapshot_count: 112, snapshot_budget: 40,
                 manifest_count: nil, manifest_budget: nil,
                 total_records: 210_000_000, delete_count: 1_200_000 } }
  end

  it "builds one row per component with the operation that fixes it" do
    rows = helper.health_component_rows(evaluation)

    frag = rows.find { |r| r[:label] == "Fragmentation" }
    expect(frag[:operation]).to eq("optimize")
    expect(frag[:pct]).to eq(58)
    expect(frag[:detail]).to include("74")
    expect(frag[:detail]).to include("128")
  end

  it "marks a component without data as missing, and reports 0 so the row keeps its shape" do
    rows = helper.health_component_rows(evaluation)
    manifests = rows.find { |r| r[:label] == "Manifests" }

    expect(manifests[:has_data]).to be(false)
    # 0 rather than nil: the view renders the track at a fixed width with an
    # empty fill, so a row without data has the same structure as one with it.
    expect(manifests[:pct]).to eq(0)
    expect(manifests[:detail]).to be_nil
  end

  it "gives snapshots a detail with the budget it is measured against" do
    rows = helper.health_component_rows(evaluation)
    snapshots = rows.find { |r| r[:label] == "Snapshots" }

    expect(snapshots[:detail]).to include("112")
    expect(snapshots[:detail]).to include("40")
  end

  it "gives manifests a detail when the count and budget are known" do
    evaluation[:details].merge!(manifest_count: 84, manifest_budget: 20)
    evaluation[:components][:manifest_buildup] = 0.2

    rows = helper.health_component_rows(evaluation)
    manifests = rows.find { |r| r[:label] == "Manifests" }

    expect(manifests[:has_data]).to be(true)
    expect(manifests[:detail]).to include("84")
    expect(manifests[:detail]).to include("20")
  end

  it "ranks severity from the ratio" do
    expect(helper.send(:severity_for, 0.3)).to eq(:critical)
    expect(helper.send(:severity_for, 0.6)).to eq(:warning)
    expect(helper.send(:severity_for, 0.9)).to eq(:ok)
    expect(helper.send(:severity_for, nil)).to eq(:none)
  end
end
