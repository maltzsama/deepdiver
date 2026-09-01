require "rails_helper"

RSpec.describe TableMetadataExtractor, type: :service do
  describe ".from_persisted" do
    let(:table) do
      create(:iceberg_table, total_records: 10_000_000, total_data_files: 200,
                             total_size_bytes: 2_000_000_000, position_deletes: 50_000,
                             equality_deletes: 0, snapshot_count: 40,
                             properties_json: { "write.target-file-size-bytes" => 64_000_000 })
    end

    it "rebuilds the extractor from the stored columns" do
      extractor = described_class.from_persisted(table)

      expect(extractor.total_records).to eq(10_000_000)
      expect(extractor.average_file_size).to eq(10_000_000)
      expect(extractor.snapshot_count).to eq(40)
      expect(extractor.position_deletes).to eq(50_000)
      expect(extractor.properties["write.target-file-size-bytes"]).to eq(64_000_000)
    end

    it "yields an unknown evaluation when nothing was synced" do
      empty = create(:iceberg_table)
      extractor = described_class.from_persisted(empty)

      result = HealthEvaluator.evaluate(extractor)
      expect(result[:score]).to be_nil
      expect(result[:status]).to eq(:unknown)
    end

    it "keeps missing fields nil, never zero" do
      partial = create(:iceberg_table, snapshot_count: 5, total_records: nil)
      extractor = described_class.from_persisted(partial)

      expect(extractor.total_records).to be_nil
      expect(extractor.position_deletes).to be_nil
    end

    it "keeps metrics when snapshot_count is zero" do
      zero = create(:iceberg_table, snapshot_count: 0, total_records: 500,
                                    total_data_files: 10, total_size_bytes: 1_000)
      extractor = described_class.from_persisted(zero)

      expect(extractor.total_records).to eq(500)
      expect(extractor.total_size_bytes).to eq(1_000)
      expect(extractor.average_file_size).to eq(100)
    end

    it "keeps metrics when snapshot_count is nil" do
      nil_count = create(:iceberg_table, snapshot_count: nil, total_records: 500,
                                         total_data_files: 10, total_size_bytes: 1_000)
      extractor = described_class.from_persisted(nil_count)

      expect(extractor.total_records).to eq(500)
      expect(extractor.total_size_bytes).to eq(1_000)
    end
  end
end
