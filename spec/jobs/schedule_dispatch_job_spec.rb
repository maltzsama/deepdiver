require "rails_helper"

RSpec.describe ScheduleDispatchJob, type: :job do
  it "runs on its own dispatch queue, separate from maintenance" do
    expect(described_class.queue_name).to eq("dispatch")
  end

  it "isolates a failing plan from the rest" do
    first = create(:maintenance_plan, cron: "* * * * *")
    second = create(:maintenance_plan, cron: "* * * * *")

    allow(MaintenanceOrchestrator).to receive(:run_plan).and_wrap_original do |original, plan_id|
      raise "boom" if plan_id == first.id

      original.call(plan_id)
    end

    described_class.perform_now

    expect(first.execution_histories.count).to eq(0)
    expect(second.execution_histories.count).to eq(1)
  end
end
