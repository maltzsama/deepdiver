require "rails_helper"

RSpec.describe FreshnessAlerter, type: :service do
  let(:sla) { create(:table_freshness_sla, sla_minutes: 120, slack_channel: "#support", email_to: "support@example.com") }

  # The alerter only decides WHEN to alert and with what payload; the actual
  # transport belongs to AlertNotifier, which has its own spec. Stub it here to
  # keep the tests focused on the alerter.
  before { allow(AlertNotifier).to receive(:notify) }

  def result_for(delay_seconds, status: "late")
    FreshnessProbe::Result.new(status: status, delay_seconds: delay_seconds, max_timestamp: Time.current)
  end

  describe "progressive severity" do
    it "stays warning under 6h of delay" do
      described_class.new(sla, result_for(3.5.hours)).call

      expect(sla.reload.severity).to eq("warning")
      expect(AlertNotifier).to have_received(:notify)
    end

    it "escalates to severe at 6h" do
      described_class.new(sla, result_for(6.hours)).call

      expect(sla.reload.severity).to eq("severe")
    end

    it "escalates to critical at 12h" do
      described_class.new(sla, result_for(12.hours)).call

      expect(sla.reload.severity).to eq("critical")
    end

    it "stays nil under 3h" do
      described_class.new(sla, result_for(2.hours)).call

      expect(sla.reload.severity).to be_nil
    end

    it "honors custom severity bands from the SLA" do
      sla.update!(warning_after_minutes: 60, severe_after_minutes: 120, critical_after_minutes: 240)

      described_class.new(sla.reload, result_for(130.minutes)).call
      expect(sla.reload.severity).to eq("severe")
    end
  end

  describe "when it alerts" do
    it "re-alerts when severity rises" do
      described_class.new(sla, result_for(3.5.hours)).call
      described_class.new(sla.reload, result_for(6.5.hours)).call

      expect(sla.reload.last_alert_level).to eq("severe")
      expect(AlertNotifier).to have_received(:notify).twice
    end

    it "does not re-alert at the same severity" do
      described_class.new(sla, result_for(3.5.hours)).call
      described_class.new(sla.reload, result_for(4.hours)).call

      expect(AlertNotifier).to have_received(:notify).once
    end

    it "does not alert when a healthy table stays ok" do
      sla.update!(status: "ok")
      described_class.new(sla, result_for(10, status: "ok")).call

      expect(AlertNotifier).not_to have_received(:notify)
    end
  end

  describe "recovery" do
    it "alerts once when a late table recovers" do
      sla.update!(status: "late", last_alert_level: "warning")
      described_class.new(sla, result_for(10, status: "ok")).call

      expect(sla.reload.status).to eq("ok")
      expect(sla.reload.last_alert_level).to eq("recovered")
      expect(AlertNotifier).to have_received(:notify) do |args|
        expect(args[:severity]).to eq("warning")
        expect(args[:context][:severity]).to eq("recovered")
      end
    end
  end

  describe "alert payload" do
    it "routes the alert through AlertNotifier with the SLA destination and rich context" do
      described_class.new(sla, result_for(3.5.hours)).call

      expect(AlertNotifier).to have_received(:notify).with(
        hash_including(
          subject: a_string_including(sla.iceberg_table.fully_qualified_name),
          severity: "warning",
          slack_channel: "#support",
          email_to: "support@example.com",
          context: hash_including(
            table: sla.iceberg_table.fully_qualified_name,
            delay: "3.5 h",
            sla: 120
          )
        )
      )
    end

    it "escalation carries the severe level" do
      described_class.new(sla, result_for(6.hours)).call

      expect(AlertNotifier).to have_received(:notify).with(
        hash_including(severity: "severe", subject: a_string_including("severe"))
      )
    end
  end
end
