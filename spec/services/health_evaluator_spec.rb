require "rails_helper"

RSpec.describe HealthEvaluator do
  def extractor(**overrides)
    instance_double(TableMetadataExtractor,
                    { average_file_size: nil, snapshot_count: nil, total_records: nil,
                      position_deletes: nil, equality_deletes: nil, properties: {} }.merge(overrides))
  end

  it "does not penalize a cold table that is well compacted" do
    result = described_class.evaluate(
      extractor(average_file_size: 130 * 1024 * 1024, snapshot_count: 5, total_records: 1000,
                position_deletes: 0, equality_deletes: 0)
    )

    expect(result[:status]).to eq(:healthy)
  end

  it "marks as critical the streaming table with tiny files" do
    result = described_class.evaluate(
      extractor(average_file_size: 2 * 1024 * 1024, snapshot_count: 900, total_records: 1_000_000,
                position_deletes: 400_000, equality_deletes: 0)
    )

    expect(result[:status]).to eq(:critical)
  end

  it "excludes a component without data instead of treating it as zero" do
    result = described_class.evaluate(extractor(average_file_size: 128 * 1024 * 1024))

    expect(result[:components][:snapshot_buildup]).to be_nil
    expect(result[:score]).to eq(100)
    expect(result[:coverage]).to eq(40)
  end

  it "returns unknown when there is no data at all" do
    expect(described_class.evaluate(extractor)[:status]).to eq(:unknown)
  end

  it "respects the table-declared target size" do
    result = described_class.evaluate(
      extractor(average_file_size: 60 * 1024 * 1024,
                properties: { "write.target-file-size-bytes" => (64 * 1024 * 1024).to_s })
    )

    expect(result[:components][:fragmentation]).to be > 0.9
  end
end
