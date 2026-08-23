require "rails_helper"

RSpec.describe HealthHelper, type: :helper do
  let(:extractor) do
    instance_double(TableMetadataExtractor,
      average_file_size: 74 * 1024 * 1024, snapshot_count: 112,
      total_records: 210_000_000, position_deletes: 1_200_000, equality_deletes: 0,
      properties: {})
  end

  let(:evaluation) do
    { score: 62, status: :warning, coverage: 90,
      components: { fragmentation: 0.58, snapshot_buildup: 0.81,
                    delete_overhead: 0.94, manifest_buildup: nil } }
  end

  it "builds one row per component with the operation that fixes it" do
    rows = helper.health_component_rows(evaluation, extractor)

    frag = rows.find { |r| r[:label] == "Fragmentation" }
    expect(frag[:operation]).to eq("optimize")
    expect(frag[:pct]).to eq(58)
    expect(frag[:detail]).to include("74")
    expect(frag[:detail]).to include("128")
  end

  it "marks a component without data as missing, not as zero" do
    rows = helper.health_component_rows(evaluation, extractor)
    manifests = rows.find { |r| r[:label] == "Manifests" }

    expect(manifests[:has_data]).to be(false)
    expect(manifests[:pct]).to be_nil
  end

  it "ranks severity from the ratio" do
    expect(helper.send(:severity_for, 0.3)).to eq(:critical)
    expect(helper.send(:severity_for, 0.6)).to eq(:warning)
    expect(helper.send(:severity_for, 0.9)).to eq(:ok)
    expect(helper.send(:severity_for, nil)).to eq(:none)
  end
end
