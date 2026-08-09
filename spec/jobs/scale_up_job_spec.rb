require "rails_helper"

RSpec.describe ScaleUpJob, type: :job do
  it "does not time out a run that waited long for the lock" do
    execution = create(:execution_history, status: :running, current_step: :scale_up,
                                           created_at: 2.hours.ago)

    expect(execution.scale_up_started_at).to be_nil
    described_class.perform_now(execution.id)

    execution.reload
    expect(execution.status).to eq("running")
    expect(execution.scale_up_started_at).not_to be_nil
  end

  it "times out when the scale-up itself exceeds the limit" do
    execution = create(:execution_history, status: :running, current_step: :scale_up)
    execution.update!(scale_up_started_at: (ScaleUpJob::SCALE_UP_TIMEOUT + 1.minute).ago)

    described_class.perform_now(execution.id)

    execution.reload
    expect(execution.status).to eq("failed")
  end
end
