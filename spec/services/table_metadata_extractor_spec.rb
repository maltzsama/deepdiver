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

    it "carries the persisted manifest_count so health inputs match everywhere" do
      table = create(:iceberg_table, manifest_count: 15)
      extractor = described_class.from_persisted(table)

      expect(extractor.manifest_count).to eq(15)
    end

    it "keeps a real window when snapshot_count is unknown and both timestamps exist" do
      oldest = 5.days.ago
      latest = Time.current
      table = create(:iceberg_table, snapshot_count: nil, total_records: 100,
                                     oldest_snapshot_at: oldest, last_data_update: latest)
      extractor = described_class.from_persisted(table)

      expect(extractor.oldest_snapshot_at).to be_present
      expect(extractor.last_snapshot_at).to be_present
      expect(extractor.oldest_snapshot_at).not_to eq(extractor.last_snapshot_at)
    end
  end

  describe "#total_size_bytes" do
    it "reads the Iceberg total-files-size key from a raw summary" do
      extractor = described_class.new(
        "current-snapshot-id" => 1,
        "snapshots" => [
          { "snapshot-id" => 1, "timestamp-ms" => 1_700_000_000_000,
            "summary" => { "total-records" => "13484606", "total-data-files" => "4689",
                           "total-files-size" => "288843674" } }
        ]
      )

      expect(extractor.total_size_bytes).to eq(288_843_674)
      expect(extractor.average_file_size).to eq(61_600)
    end

    it "returns nil when the summary lacks total-files-size" do
      extractor = described_class.new(
        "current-snapshot-id" => 1,
        "snapshots" => [ { "snapshot-id" => 1, "summary" => { "total-records" => "5" } } ]
      )

      expect(extractor.total_size_bytes).to be_nil
    end
  end
end
