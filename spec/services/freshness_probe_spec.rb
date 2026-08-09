require "rails_helper"

RSpec.describe FreshnessProbe do
  let(:table) { create(:iceberg_table) }
  let(:client) { instance_double(TrinoClient) }

  def sla(**overrides)
    create(:table_freshness_sla, {
      iceberg_table: table, enabled: true, timestamp_column: "load_timestamp",
      partition_column: "dt", partition_lookback: 7, sla_minutes: 120
    }.merge(overrides))
  end

  describe "partition pruning" do
    it "uses the N most recent partitions without arithmetic on the int" do
      expect(client).to receive(:query_column)
        .with(/ORDER BY p DESC\s+LIMIT 7/, "p")
        .and_return([ 20_260_807, 20_260_806, 20_260_801 ])

      expect(client).to receive(:query_scalar)
        .with(/IN \(20260807, 20260806, 20260801\)/, "max_ts")
        .and_return(Time.current)

      described_class.new(sla, client:).call
    end

    it "does not break at the month boundary" do
      allow(client).to receive(:query_column).and_return([ 20_260_801, 20_260_731 ])
      allow(client).to receive(:query_scalar).and_return(Time.current)

      expect(described_class.new(sla, client:).call.status).to eq("ok")
    end

    it "quotes a textual partition" do
      allow(client).to receive(:query_column).and_return(%w[2026-08-07])
      expect(client).to receive(:query_scalar).with(/IN \('2026-08-07'\)/, "max_ts")
                                              .and_return(Time.current)

      described_class.new(sla, client:).call
    end
  end

  describe "timestamp normalization" do
    before { allow(client).to receive(:query_column).and_return([ 20_260_807 ]) }

    it "epoch in seconds" do
      now = Time.utc(2026, 8, 9, 12, 0, 0)
      allow(client).to receive(:query_scalar).and_return((now - 30.minutes).to_i)

      result = described_class.new(sla(timestamp_type: "epoch_seconds"), client:, now:).call

      expect(result.delay_seconds).to be_within(2).of(1800)
      expect(result.status).to eq("ok")
    end

    it "epoch in milliseconds" do
      now = Time.utc(2026, 8, 9, 12, 0, 0)
      allow(client).to receive(:query_scalar).and_return(((now - 30.minutes).to_f * 1000).to_i)

      result = described_class.new(sla(timestamp_type: "epoch_millis"), client:, now:).call

      expect(result.delay_seconds).to be_within(2).of(1800)
    end

    it "compensates epoch written in a local timezone" do
      now = Time.utc(2026, 8, 9, 12, 0, 0)
      wall_clock = Time.utc(2026, 8, 9, 13, 30, 0) # 13:30 local = 11:30 UTC in summer

      allow(client).to receive(:query_scalar).and_return(wall_clock.to_i)

      result = described_class.new(
        sla(timestamp_type: "epoch_seconds", source_timezone: "Europe/Stockholm"),
        client:, now:
      ).call

      # Without compensation the delay would come out NEGATIVE (data from the
      # future).
      expect(result.delay_seconds).to be_positive
    end
  end

  describe "classification" do
    before { allow(client).to receive(:query_column).and_return([ 20_260_807 ]) }

    it "late when past the SLA" do
      allow(client).to receive(:query_scalar).and_return(5.hours.ago)
      expect(described_class.new(sla, client:).call.status).to eq("late")
    end

    it "warning when past the warning percent" do
      allow(client).to receive(:query_scalar).and_return(110.minutes.ago)
      expect(described_class.new(sla, client:).call.status).to eq("warning")
    end

    it "no_data when there is nothing in the partitions seen" do
      allow(client).to receive(:query_scalar).and_return(nil)
      expect(described_class.new(sla, client:).call.status).to eq("no_data")
    end

    it "error when the query fails, without raising" do
      allow(client).to receive(:query_column).and_raise("Trino down")
      result = described_class.new(sla, client:).call

      expect(result.status).to eq("error")
      expect(result.error_message).to include("Trino")
    end
  end
end
