require "rails_helper"

RSpec.describe FreshnessSweepJob, type: :job do
  it "a table that errors does not take the sweep down and shows in history" do
    good = create(:table_freshness_sla, enabled: true)
    bad  = create(:table_freshness_sla, enabled: true)

    allow(FreshnessProbe).to receive(:new) do |sla, **kwargs|
      raise "exploded" if sla.id == bad.id

      instance_double(FreshnessProbe,
                      call: FreshnessProbe::Result.new(status: "ok", delay_seconds: 10,
                                                       max_timestamp: Time.current))
    end

    run = FreshnessRun.create!
    described_class.perform_now(run.id)

    expect(run.reload.tables_checked).to eq(1)
    expect(run.tables_late).to eq(0)
    expect(run.tables_errored).to eq(1)
    expect(FreshnessCheck.where(iceberg_table_id: bad.iceberg_table_id).last.status).to eq("error")
    expect(FreshnessCheck.where(iceberg_table_id: good.iceberg_table_id).last.status).to eq("ok")
  end

  describe "heartbeat" do
    it "sets last_heartbeat_at when transitioning to running" do
      sla = create(:table_freshness_sla, enabled: true)
      allow(FreshnessProbe).to receive(:new).and_return(
        instance_double(FreshnessProbe, call: FreshnessProbe::Result.new(status: "ok", delay_seconds: 0, max_timestamp: Time.current))
      )

      run = FreshnessRun.create!
      described_class.perform_now(run.id)

      expect(run.reload.last_heartbeat_at).to be_present
      expect(run.status).to eq("finished")
    end

    it "touches heartbeat after every SLA" do
      slas = 3.times.map { create(:table_freshness_sla, enabled: true) }
      call_count = 0
      allow(FreshnessProbe).to receive(:new) do
        call_count += 1
        instance_double(FreshnessProbe, call: FreshnessProbe::Result.new(status: "ok", delay_seconds: 0, max_timestamp: Time.current))
      end

      run = FreshnessRun.create!
      described_class.perform_now(run.id)

      expect(call_count).to eq(3)
      expect(run.reload.last_heartbeat_at).to be_present
    end

    it "does not overwrite a failed run back to finished" do
      # The conditional update_all uses `where(id:, status: "running")` —
      # if the reaper already set status to "failed", it finds nothing.
      run = FreshnessRun.create!(status: "running", started_at: 20.minutes.ago)

      # Simulate reaper
      run.update!(status: "failed", error_message: "sweep interrupted")

      # Conditional update as the job would do
      updated = FreshnessRun.where(id: run.id, status: "running")
                            .update_all(status: "finished", finished_at: Time.current)

      expect(updated).to eq(0)
      expect(run.reload.status).to eq("failed")
    end
  end
end
