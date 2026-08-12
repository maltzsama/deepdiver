require "rails_helper"

RSpec.describe AlertChannelNotifier, type: :service do
  let!(:alert_setting) { create(:alert_setting) }

  describe ".notify" do
    it "sends to every enabled channel at or above the severity" do
      slack = create(:alert_channel, :slack)
      email = create(:alert_channel, :email)

      allow(SlackAlert).to receive(:notify)
      allow(AlertMailer).to receive_message_chain(:alert, :deliver_now)

      described_class.notify(subject: "Problem", message: "Something broke", severity: "warning")

      expect(SlackAlert).to have_received(:notify).with(
        "Problem: Something broke",
        webhook: alert_setting.slack_webhook,
        channel: "#alerts"
      )
      expect(AlertMailer).to have_received(:alert).with(
        to: "support@example.com", subject: "Problem", body: "Problem: Something broke"
      )
      expect(slack.reload.last_sent_at).to be_present
      expect(email.reload.last_sent_at).to be_present
    end

    it "skips channels whose minimum severity is above the alert" do
      create(:alert_channel, :slack, min_severity: "critical")

      allow(SlackAlert).to receive(:notify)
      described_class.notify(subject: "Problem", message: "meh", severity: "warning")

      expect(SlackAlert).not_to have_received(:notify)
    end

    it "skips channels in cooldown" do
      create(:alert_channel, :slack, cooldown_minutes: 60, last_sent_at: 5.minutes.ago)

      allow(SlackAlert).to receive(:notify)
      described_class.notify(subject: "Problem", message: "again", severity: "warning")

      expect(SlackAlert).not_to have_received(:notify)
    end

    it "ignores disabled channels" do
      create(:alert_channel, :slack, enabled: false)

      allow(SlackAlert).to receive(:notify)
      described_class.notify(subject: "Problem", message: "meh", severity: "warning")

      expect(SlackAlert).not_to have_received(:notify)
    end

    it "renders the channel's message template with context variables" do
      create(:alert_channel, :slack,
             message_template: "[%{severity}] %{subject} on %{table}: %{message}")

      allow(SlackAlert).to receive(:notify)
      described_class.notify(
        subject: "Late", message: "table behind",
        severity: "severe",
        context: { table: "catalog.schema.orders" }
      )

      expect(SlackAlert).to have_received(:notify).with(
        "[severe] Late on catalog.schema.orders: table behind",
        webhook: alert_setting.slack_webhook,
        channel: "#alerts"
      )
    end

    it "records an error on the channel when Slack fails" do
      channel = create(:alert_channel, :slack)
      allow(SlackAlert).to receive(:notify).and_raise("boom")

      expect { described_class.notify(subject: "Problem", message: "x", severity: "warning") }
        .not_to raise_error

      expect(channel.reload.last_error).to eq("boom")
    end

    it "does not email when no webhook is configured but email exists" do
      alert_setting.update!(slack_webhook_url: nil)
      create(:alert_channel, :email)

      allow(AlertMailer).to receive_message_chain(:alert, :deliver_now)
      described_class.notify(subject: "Problem", message: "x", severity: "warning")

      expect(AlertMailer).to have_received(:alert)
    end
  end

  describe "#deliver_to!" do
    it "sends through the given channel regardless of cooldown or severity" do
      channel = create(:alert_channel, :slack, min_severity: "critical",
                       cooldown_minutes: 60, last_sent_at: 1.minute.ago)
      allow(SlackAlert).to receive(:notify)

      described_class.new(subject: "Test", message: "ping", severity: "warning").deliver_to!(channel)

      expect(SlackAlert).to have_received(:notify)
    end
  end
end
