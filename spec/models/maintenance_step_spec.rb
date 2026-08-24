require "rails_helper"

RSpec.describe MaintenanceStep do
  let(:plan) { create(:maintenance_plan, cron: "0 * * * *") }

  describe "#due_at?" do
    it "is always due without a cadence" do
      step = create(:maintenance_step, maintenance_plan: plan, operation: "optimize", position: 0)

      expect(step.due_at?(Time.zone.parse("2026-08-10 02:00"))).to be true
    end

    it "is due only when the cadence matches the instant" do
      step = create(:maintenance_step, maintenance_plan: plan, operation: "expire_snapshots",
                                       position: 1, cadence_cron: "0 3 * * *")

      expect(step.due_at?(Time.zone.parse("2026-08-10 03:00"))).to be true
      expect(step.due_at?(Time.zone.parse("2026-08-10 02:00"))).to be false
    end
  end

  describe "cadence validation" do
    it "rejects a cadence that never coincides with the plan cron" do
      step = build(:maintenance_step, maintenance_plan: plan, operation: "optimize",
                                      position: 9, cadence_cron: "30 3 * * *")

      expect(step).not_to be_valid
      expect(step.errors[:cadence_cron].join).to include("never coincides")
    end

    it "accepts an aligned cadence" do
      step = build(:maintenance_step, maintenance_plan: plan, operation: "optimize",
                                      position: 9, cadence_cron: "0 * * * *")

      expect(step).to be_valid
    end
  end

  describe "config validation" do
    it "accepts well-formed thresholds and integer snapshot ids" do
      step = build(:maintenance_step, maintenance_plan: plan, operation: "expire_snapshots",
                                      position: 0, config: {
                                        "retention_threshold" => "7d",
                                        "file_size_threshold" => "128MB",
                                        "snapshot_ids" => "123, 456"
                                      })

      expect(step).to be_valid
    end

    it "rejects a retention_threshold that is not a magnitude plus unit" do
      step = build(:maintenance_step, maintenance_plan: plan, operation: "expire_snapshots",
                                      position: 0, config: { "retention_threshold" => "7d; DROP TABLE x" })

      expect(step).not_to be_valid
      expect(step.errors[:config].join).to include("retention_threshold")
    end

    it "rejects a file_size_threshold that is not a magnitude plus unit" do
      step = build(:maintenance_step, maintenance_plan: plan, operation: "optimize",
                                      position: 0, config: { "file_size_threshold" => "128MB OR 1=1" })

      expect(step).not_to be_valid
      expect(step.errors[:config].join).to include("file_size_threshold")
    end

    it "rejects snapshot_ids that are not integers" do
      step = build(:maintenance_step, maintenance_plan: plan, operation: "expire_snapshots",
                                      position: 0, config: { "snapshot_ids" => "1, 2; DROP TABLE x" })

      expect(step).not_to be_valid
      expect(step.errors[:config].join).to include("snapshot_ids")
    end

    it "ignores config without the validated keys" do
      step = build(:maintenance_step, maintenance_plan: plan, operation: "optimize",
                                      position: 0, config: { "where" => "1 = 1" })

      expect(step).to be_valid
    end
  end
end
