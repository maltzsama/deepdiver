require "rails_helper"

RSpec.describe TableMetadataExtractor, ".from_persisted" do
  let(:now) { Time.zone.parse("2026-09-02 12:00:00") }

  # Builds `recent` snapshots inside the reference window and `old` ones outside it.
  def snapshots(recent:, old:)
    list = []
    old.times    { |i| list << { "timestamp-ms" => ((now - (30 - i * 0.1).days).to_f * 1000).to_i, "snapshot-id" => i } }
    recent.times { |i| list << { "timestamp-ms" => ((now - (6 - i * 0.05).days).to_f * 1000).to_i, "snapshot-id" => 1000 + i } }
    list
  end

  it "uses the real persisted snapshots, so every entry keeps its timestamp" do
    list = snapshots(recent: 40, old: 60)
    table = create(:iceberg_table, snapshot_count: list.size, snapshots_json: list,
                   oldest_snapshot_at: now - 30.days, last_data_update: now)

    extractor = described_class.from_persisted(table)

    expect(extractor.snapshots.size).to eq(100)
    expect(extractor.snapshots.count { |s| s["timestamp-ms"] }).to eq(100)
  end

  it "still exposes the summary metrics rebuilt from the persisted columns" do
    list = snapshots(recent: 5, old: 5)
    table = create(:iceberg_table, snapshot_count: list.size, snapshots_json: list,
                   oldest_snapshot_at: now - 30.days, last_data_update: now,
                   total_records: 1_000_000, total_data_files: 4689,
                   total_size_bytes: 288_843_674, manifest_count: 12)

    extractor = described_class.from_persisted(table)

    expect(extractor.total_records).to eq(1_000_000)
    expect(extractor.total_data_files).to eq(4689)
    expect(extractor.total_size_bytes).to eq(288_843_674)
    expect(extractor.manifest_count).to eq(12)
  end

  it "does not mutate the persisted snapshots_json" do
    list = snapshots(recent: 2, old: 0)
    table = create(:iceberg_table, snapshot_count: list.size, snapshots_json: list,
                   last_data_update: now, total_records: 10)

    described_class.from_persisted(table)

    expect(table.reload.snapshots_json.last).not_to have_key("summary")
  end

  it "produces a snapshot_buildup that varies with the snapshot count" do
    # Same window, very different counts: the score must distinguish them.
    tidy = create(:iceberg_table, snapshot_count: 20,
                  snapshots_json: snapshots(recent: 20, old: 0),
                  oldest_snapshot_at: now - 6.days, last_data_update: now)
    behind = create(:iceberg_table, snapshot_count: 220,
                    snapshots_json: snapshots(recent: 20, old: 200),
                    oldest_snapshot_at: now - 30.days, last_data_update: now)

    tidy_ratio   = HealthEvaluator.evaluate(described_class.from_persisted(tidy), now: now)[:components][:snapshot_buildup]
    behind_ratio = HealthEvaluator.evaluate(described_class.from_persisted(behind), now: now)[:components][:snapshot_buildup]

    expect(tidy_ratio).to be > behind_ratio
    expect(tidy_ratio).to be > 0.0
  end

  context "when no real snapshots are persisted" do
    it "falls back to the synthetic list and still surfaces the summary" do
      table = create(:iceberg_table, snapshot_count: 0, snapshots_json: nil,
                     oldest_snapshot_at: now - 3.days, last_data_update: now,
                     total_records: 500, total_data_files: 12)

      extractor = described_class.from_persisted(table)

      expect(extractor.total_records).to eq(500)
      expect(extractor.total_data_files).to eq(12)
    end

    it "keeps the observed window across two entries rather than aliasing one" do
      table = create(:iceberg_table, snapshot_count: 0, snapshots_json: nil,
                     oldest_snapshot_at: now - 3.days, last_data_update: now,
                     total_records: 500)

      extractor = described_class.from_persisted(table)

      expect(extractor.oldest_snapshot_at).to be_within(1).of(now - 3.days)
      expect(extractor.last_snapshot_at).to be_within(1).of(now)
    end

    it "stays unknown when nothing has been synced" do
      table = create(:iceberg_table, snapshot_count: 0, snapshots_json: nil,
                     total_records: nil, total_data_files: nil, total_size_bytes: nil,
                     position_deletes: nil, equality_deletes: nil, manifest_count: nil,
                     oldest_snapshot_at: nil, last_data_update: nil)

      extractor = described_class.from_persisted(table)

      expect(extractor.snapshots).to be_empty
      expect(extractor.total_records).to be_nil
    end
  end
end
