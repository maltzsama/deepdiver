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
end
