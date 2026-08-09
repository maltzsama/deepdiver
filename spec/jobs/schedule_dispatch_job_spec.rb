require "rails_helper"

RSpec.describe ScheduleDispatchJob, type: :job do
  it "isolates a failing schedule from the rest" do
    first = create(:maintenance_schedule, cron: "* * * * *")
    second = create(:maintenance_schedule, operation: "expire_snapshots", cron: "* * * * *")

    allow(MaintenanceOrchestrator).to receive(:run_schedule).and_wrap_original do |original, schedule_id|
      raise "boom" if schedule_id == first.id

      original.call(schedule_id)
    end

    described_class.perform_now

    expect(first.execution_histories.count).to eq(0)
    expect(second.execution_histories.count).to eq(1)
  end
end
