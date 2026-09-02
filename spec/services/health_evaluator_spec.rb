require "rails_helper"

RSpec.describe HealthEvaluator do
  def extractor(**overrides)
    instance_double(TableMetadataExtractor,
                    { average_file_size: nil, snapshot_count: nil, total_records: nil,
                      position_deletes: nil, equality_deletes: nil, properties: {},
                      oldest_snapshot_at: nil, last_snapshot_at: nil, manifest_count: nil,
                      snapshots: [] }.merge(overrides))
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

  it "reports the worst component even when the composite is diluted" do
    # The exact shape from #185: severe fragmentation (60 KB vs 64 MB target)
    # diluted by healthy snapshot/delete/manifest signals still scores ~60.
    result = described_class.evaluate(
      extractor(
        average_file_size: 60 * 1024, snapshot_count: 5, total_records: 10_000_000,
        position_deletes: 0, equality_deletes: 0, properties: { "write.target-file-size-bytes" => (64 * 1024 * 1024).to_s },
        oldest_snapshot_at: 7.days.ago, last_snapshot_at: Time.current
      ),
      manifest_count: 3
    )

    expect(result[:score]).to be >= 55
    expect(result[:worst_component]).to eq(:fragmentation)
    expect(result[:worst_ratio]).to be < 0.01
  end

  it "leaves worst_component nil when nothing is measurable" do
    expect(described_class.evaluate(extractor)[:worst_component]).to be_nil
  end

  it "reads manifest_count from the extractor when no keyword is passed" do
    table = create(:iceberg_table, snapshot_count: 5, total_records: 1000,
                                   manifest_count: 2)
    result = described_class.evaluate(TableMetadataExtractor.from_persisted(table))

    expect(result[:components][:manifest_buildup]).to be_present
  end

  describe "fragmentation log scale" do
    let(:target) { (64 * 1024 * 1024).to_s }

    def frag(average)
      described_class.evaluate(
        extractor(average_file_size: average,
                  properties: { "write.target-file-size-bytes" => target })
      )[:components][:fragmentation]
    end

    it "scores at-target tables at 1.0" do
      expect(frag(64 * 1024 * 1024)).to eq(1.0)
    end

    it "scores ~10x below target around 0.67" do
      expect(frag(6 * 1024 * 1024)).to be_within(0.05).of(0.67)
    end

    it "scores ~1000x below target at 0.0" do
      expect(frag(64 * 1024)).to eq(0.0)
    end

    it "separates tables that the linear ratio collapsed" do
      # 819 KB vs 1.29 MB: linear gave 0.0122 vs 0.0192 (indistinguishable);
      # log gives ~0.37 vs ~0.43 — the less-fragmented table scores higher.
      expect(frag(819 * 1024)).to be < frag(1_290 * 1024)
    end
  end

  describe "snapshot_buildup budget" do
    let(:plan) { create(:maintenance_plan, :with_all_steps) }

    def busy_extractor(count:, oldest:, latest:)
      snapshots = Array.new(count) do |i|
        ts = oldest.to_f + ((latest.to_f - oldest.to_f) * (i.to_f / [ count - 1, 1 ].max))
        { "timestamp-ms" => (ts * 1000).to_i }
      end
      extractor(
        average_file_size: 128 * 1024 * 1024,
        snapshot_count: count, oldest_snapshot_at: oldest, last_snapshot_at: latest,
        total_records: 1_000_000, position_deletes: 0, equality_deletes: 0,
        snapshots: snapshots
      )
    end

    it "scores a busy table (committing hourly) healthy right after expire" do
      # 7 days of hourly commits = 168 snapshots, all inside the reference
      # window; budget ≈ 168 so the score is high.
      oldest = 7.days.ago
      latest = Time.current
      result = described_class.evaluate(busy_extractor(count: 168, oldest:, latest:), plan:)

      expect(result[:components][:snapshot_buildup]).to be > 0.9
      expect(result[:status]).to eq(:healthy)
    end

    it "scores the same span differently by count — the count no longer cancels" do
      # Identical 30-day window: 1 000 snapshots all recent score high, while
      # 2 000 snapshots spread over the same span (half older than the window)
      # score low.
      oldest = 30.days.ago
      latest = Time.current
      recent_span = [ 1_000, 7.days ].max
      recent_count = described_class.new(
        busy_extractor(count: 1_000, oldest: 7.days.ago, latest: Time.current), plan:
      ).call[:components][:snapshot_buildup]

      backlog_count = described_class.new(
        busy_extractor(count: 2_000, oldest:, latest:), plan:
      ).call[:components][:snapshot_buildup]

      expect(recent_count).to be > backlog_count
    end

    it "does not reward raising retention for a fixed snapshot count" do
      # 720 snapshots over 30 days: only the recent ~168 fall inside the
      # reference window, so the table is over-budget; a longer retention must
      # not make it healthier.
      oldest = 30.days.ago
      latest = Time.current
      step = plan.maintenance_steps.find_by!(operation: "expire_snapshots")
      step.update!(config: { "retention_threshold" => "1 day" })
      tight = described_class.new(busy_extractor(count: 720, oldest:, latest:), plan:)
      tight_score = tight.call[:components][:snapshot_buildup]

      step.update!(config: { "retention_threshold" => "30 days" })
      loose = described_class.new(busy_extractor(count: 720, oldest:, latest:), plan:)
      loose_score = loose.call[:components][:snapshot_buildup]

      # The budget comes from the reference window, decoupled from the
      # configurable retention — raising retention changes nothing.
      expect(tight_score).to eq(loose_score)
      expect(tight_score).to be < 0.1
    end
  end
end
