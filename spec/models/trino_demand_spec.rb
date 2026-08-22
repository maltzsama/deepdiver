require "rails_helper"

RSpec.describe TrinoDemand do
  it "counts an execution awaiting a retry as active demand" do
    create(:execution_history, status: :running, retry_count: 2)

    expect(described_class.count).to eq(1)
  end

  it "marks as failed an execution without a heartbeat and stops counting it" do
    orphan = create(:execution_history, status: :running, last_heartbeat_at: 20.minutes.ago)

    expect(described_class.count).to eq(0)
    expect(orphan.reload.status).to eq("failed")
    expect(orphan.error_message).to include("coordinator")
  end

  it "does not kill a long execution that keeps signalling" do
    alive = create(:execution_history, status: :running, last_heartbeat_at: 1.minute.ago)

    expect(described_class.count).to eq(1)
    expect(alive.reload.status).to eq("running")
  end

  describe "freshness run reaping" do
    it "reaps a freshness run without heartbeat beyond STALE_AFTER" do
      run = FreshnessRun.create!(status: "running", started_at: 20.minutes.ago)

      expect(described_class.count).to eq(0)
      expect(run.reload.status).to eq("failed")
      expect(run.error_message).to eq("sweep interrupted")
    end

    it "does not reap a freshness run that keeps heartbeating" do
      run = FreshnessRun.create!(status: "running", started_at: 20.minutes.ago,
                                 last_heartbeat_at: 1.minute.ago)

      expect(described_class.count).to eq(1)
      expect(run.reload.status).to eq("running")
    end

    it "uses COALESCE to cover runs without last_heartbeat_at" do
      run = FreshnessRun.create!(status: "running", started_at: 20.minutes.ago,
                                 last_heartbeat_at: nil)

      expect(described_class.count).to eq(0)
      expect(run.reload.status).to eq("failed")
    end
  end
end
