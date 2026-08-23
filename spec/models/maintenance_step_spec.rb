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
end
