require "rails_helper"

RSpec.describe HealthEvaluator do
  def extractor(**overrides)
    instance_double(TableMetadataExtractor,
                    { average_file_size: nil, snapshot_count: nil, total_records: nil,
                      position_deletes: nil, equality_deletes: nil, properties: {},
                      oldest_snapshot_at: nil, last_snapshot_at: nil }.merge(overrides))
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

  describe "snapshot_buildup budget" do
    let(:plan) { create(:maintenance_plan, :with_all_steps) }

    def busy_extractor(count:, oldest:, latest:)
      extractor(
        average_file_size: 128 * 1024 * 1024,
        snapshot_count: count, oldest_snapshot_at: oldest, last_snapshot_at: latest,
        total_records: 1_000_000, position_deletes: 0, equality_deletes: 0
      )
    end

    it "scores a busy table (committing hourly) healthy right after expire" do
      # 7 days of hourly commits = 168 snapshots; expire should leave ~168.
      oldest = 7.days.ago
      latest = Time.current
      result = described_class.evaluate(busy_extractor(count: 168, oldest:, latest:), plan:)

      expect(result[:components][:snapshot_buildup]).to be > 0.9
      expect(result[:status]).to eq(:healthy)
    end

    it "derives the budget from the real commit rate, not a fixed 10/day" do
      oldest = 7.days.ago
      latest = Time.current
      evaluator = described_class.new(busy_extractor(count: 168, oldest:, latest:), plan:)

      expect(evaluator.send(:observed_snapshots_per_day)).to be_within(0.1).of(24)
    end

    it "does not reward raising retention for a fixed snapshot count" do
      # 30 days of hourly commits = 720 snapshots. Budget = rate(24/day) × fixed
      # 7-day window = 168. The table is over-budget (expire is not running).
      oldest = 30.days.ago
      latest = Time.current
      step = plan.maintenance_steps.find_by!(operation: "expire_snapshots")
      step.update!(config: { "retention_threshold" => "1 day" })
      tight = described_class.new(busy_extractor(count: 720, oldest:, latest:), plan:)
      tight_score = tight.call[:components][:snapshot_buildup]

      step.update!(config: { "retention_threshold" => "30 days" })
      loose = described_class.new(busy_extractor(count: 720, oldest:, latest:), plan:)
      loose_score = loose.call[:components][:snapshot_buildup]

      # The budget is rate-based over a fixed reference window, decoupled from
      # the configurable retention — raising retention changes nothing.
      expect(tight_score).to eq(loose_score)
      expect(tight_score).to be < 0.1
    end
  end
end
