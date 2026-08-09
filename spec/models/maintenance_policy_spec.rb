require "rails_helper"

RSpec.describe MaintenancePolicy do
  let(:catalog) { create(:catalog) }
  let(:tables)  { create_list(:iceberg_table, 3, catalog:) }

  let(:policy) do
    described_class.create!(
      name: "Streaming optimize", operation: "optimize",
      cron: "0 */6 * * *", config: { "file_size_threshold" => "256MB" }
    )
  end

  describe "validations" do
    it "rejects an invalid cron" do
      p = described_class.new(name: "x", operation: "optimize", cron: "0 99 99 99 99")

      expect(p).not_to be_valid
      expect(p.errors[:cron]).to be_present
    end

    it "rejects an operation outside the list" do
      p = described_class.new(name: "x", operation: "rewrite_manifests", cron: "0 3 * * *")

      expect(p).not_to be_valid
    end

    it "cleans blank params coming from the form" do
      p = described_class.create!(name: "y", operation: "optimize", cron: "0 3 * * *",
                                  config: { "file_size_threshold" => "", "retention_threshold" => "7d" })

      expect(p.config).to eq("retention_threshold" => "7d")
    end
  end

  describe "#apply_to!" do
    it "creates one schedule per table" do
      result = policy.apply_to!(tables)

      expect(result).to eq(created: 3, updated: 0, skipped: 0)
      expect(policy.maintenance_schedules.count).to eq(3)
      expect(policy.maintenance_schedules.first.cron).to eq("0 */6 * * *")
      expect(policy.maintenance_schedules.first.config).to eq("file_size_threshold" => "256MB")
    end

    it "adopts an existing schedule that has no policy yet" do
      orphan = create(:maintenance_schedule, iceberg_table: tables.first,
                                             operation: "optimize", cron: "0 1 * * *")

      result = policy.apply_to!([ tables.first ])

      expect(result).to eq(created: 0, updated: 1, skipped: 0)
      expect(orphan.reload.maintenance_policy).to eq(policy)
      expect(orphan.cron).to eq("0 */6 * * *")
    end

    it "is idempotent: reapplying does not duplicate" do
      policy.apply_to!(tables)
      result = policy.apply_to!(tables)

      expect(result).to eq(created: 0, updated: 3, skipped: 0)
      expect(policy.maintenance_schedules.count).to eq(3)
    end

    it "does NOT steal a schedule from another policy" do
      other_policy = described_class.create!(name: "Batch optimize", operation: "optimize",
                                             cron: "0 3 * * *")
      other_policy.apply_to!([ tables.first ])

      result = policy.apply_to!([ tables.first ])

      expect(result).to eq(created: 0, updated: 0, skipped: 1)
      expect(tables.first.maintenance_schedules.first.maintenance_policy).to eq(other_policy)
    end

    it "does not collide with a schedule of another operation on the same table" do
      create(:maintenance_schedule, iceberg_table: tables.first, operation: "expire_snapshots")

      result = policy.apply_to!([ tables.first ])

      expect(result).to eq(created: 1, updated: 0, skipped: 0)
    end
  end

  describe "#propagate!" do
    before { policy.apply_to!(tables) }

    it "syncs cron and parameters to every schedule" do
      policy.update!(cron: "0 */4 * * *", config: { "file_size_threshold" => "512MB" })
      count = policy.propagate!

      expect(count).to eq(3)
      expect(policy.maintenance_schedules.pluck(:cron).uniq).to eq([ "0 */4 * * *" ])
      expect(policy.maintenance_schedules.first.config).to eq("file_size_threshold" => "512MB")
    end

    it "PRESERVES a pause from repeated failures" do
      paused = policy.maintenance_schedules.first
      paused.update!(is_paused: true, consecutive_failures: 3)

      policy.update!(cron: "0 */4 * * *")
      policy.propagate!

      expect(paused.reload).to be_paused
      expect(paused.consecutive_failures).to eq(3)
      expect(paused.cron).to eq("0 */4 * * *")
    end
  end

  describe "destruction" do
    it "does not delete the schedules, only unlinks them" do
      policy.apply_to!(tables)

      expect { policy.destroy }.not_to change(MaintenanceSchedule, :count)
      expect(MaintenanceSchedule.pluck(:maintenance_policy_id).uniq).to eq([ nil ])
    end
  end
end
