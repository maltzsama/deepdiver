require "rails_helper"

RSpec.describe AlertNotifier, type: :service do
  let!(:alert_setting) { create(:alert_setting) }

  describe ".notify" do
    it "sends to the given Slack channel and email recipients" do
      allow(SlackAlert).to receive(:notify)
      allow(AlertMailer).to receive_message_chain(:alert, :deliver_now)

      described_class.notify(
        subject: "Problem", message: "Something broke", severity: "warning",
        slack_channel: "#support", email_to: "ops@example.com"
      )

      expect(SlackAlert).to have_received(:notify).with(
        "Something broke",
        webhook: alert_setting.slack_webhook,
        channel: "#support"
      )
      expect(AlertMailer).to have_received(:alert).with(
        to: "ops@example.com", subject: "Problem", body: "Something broke"
      )
    end

    it "only sends to Slack when no email is given" do
      allow(SlackAlert).to receive(:notify)
      allow(AlertMailer).to receive_message_chain(:alert, :deliver_now)

      described_class.notify(subject: "Problem", message: "meh", severity: "warning", slack_channel: "#support")

      expect(SlackAlert).to have_received(:notify)
      expect(AlertMailer).not_to have_received(:alert)
    end

    it "only sends to email when no Slack channel is given" do
      allow(SlackAlert).to receive(:notify)
      allow(AlertMailer).to receive_message_chain(:alert, :deliver_now)

      described_class.notify(subject: "Problem", message: "meh", severity: "warning", email_to: "ops@example.com")

      expect(SlackAlert).not_to have_received(:notify)
      expect(AlertMailer).to have_received(:alert)
    end

    it "returns nil when delivered" do
      allow(SlackAlert).to receive(:notify)

      expect(described_class.notify(subject: "P", message: "m", severity: "warning", slack_channel: "#x")).to be_nil
    end

    it "returns an error when no Slack webhook is configured" do
      alert_setting.update!(slack_webhook_url: nil)
      allow(SlackAlert).to receive(:notify)

      error = described_class.notify(subject: "P", message: "m", severity: "warning", slack_channel: "#x")

      expect(error).to include("webhook")
      expect(SlackAlert).not_to have_received(:notify)
    end

    it "returns an error when Slack raises" do
      allow(SlackAlert).to receive(:notify).and_raise("boom")

      error = described_class.notify(subject: "P", message: "m", severity: "warning", slack_channel: "#x")

      expect(error).to eq("boom")
    end
  end
end
