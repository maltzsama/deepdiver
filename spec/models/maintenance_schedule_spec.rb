require "rails_helper"

RSpec.describe MaintenanceSchedule, type: :model do
  describe "config validation" do
    it "accepts blank config values submitted by the form" do
      schedule = build(:maintenance_schedule, operation: "expire_snapshots",
                                              config: { "file_size_threshold" => "", "retention_threshold" => "" })

      expect(schedule).to be_valid
      expect(schedule.config).to eq({})
    end
  end

  describe "cron validation" do
    it "accepts a valid cron expression" do
      expect(build(:maintenance_schedule, cron: "0 3 * * *")).to be_valid
    end

    it "rejects a cron with out-of-range fields" do
      schedule = build(:maintenance_schedule, cron: "0 99 99 99 99")

      expect(schedule).not_to be_valid
      expect(schedule.errors[:cron]).to include("is not a valid cron expression")
    end

    it "rejects a non-cron string" do
      expect(build(:maintenance_schedule, cron: "not a cron")).not_to be_valid
    end
  end
end
