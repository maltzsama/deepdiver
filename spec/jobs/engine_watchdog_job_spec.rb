require "rails_helper"

RSpec.describe EngineWatchdogJob, type: :job do
  it "marks a stuck starting engine as failed after the multi-attempt window" do
    state = TrinoEngineSupervisor.state
    state.update!(status: "starting", status_changed_at: 30.minutes.ago)

    described_class.perform_now

    expect(state.reload.status).to eq("failed")
    expect(state.last_error).to include("watchdog")
  end

  it "does not fail a starting engine still within the multi-attempt window" do
    state = TrinoEngineSupervisor.state
    state.update!(status: "starting", status_changed_at: Time.current)

    described_class.perform_now

    expect(state.reload.status).to eq("starting")
  end

  it "covers the full retry span across all start attempts" do
    window = EngineWatchdogJob::START_STUCK_AFTER
    single = TrinoEngineSupervisor::READY_TIMEOUT + 2.minutes

    expect(window).to be > single
    expect(window).to eq((TrinoEngineSupervisor::READY_TIMEOUT * TrinoEngineSupervisor::MAX_START_ATTEMPTS) + 2.minutes)
  end

  it "marks a stuck draining engine as failed" do
    state = TrinoEngineSupervisor.state
    state.update!(status: "draining", status_changed_at: 60.minutes.ago)

    described_class.perform_now

    expect(state.reload.status).to eq("failed")
  end
end
