require "rails_helper"

RSpec.describe AlertSetting, type: :model do
  describe ".instance" do
    it "returns the singleton record" do
      first = described_class.instance
      expect(described_class.instance).to eq(first)
    end
  end

  describe "#slack_webhook" do
    it "returns nil when not configured" do
      expect(build(:alert_setting, slack_webhook_url: nil).slack_webhook).to be_nil
    end

    it "returns the URL when configured" do
      expect(build(:alert_setting).slack_webhook).to eq("https://hooks.slack.com/services/T000/B000/XXXX")
    end
  end

  describe "#smtp_settings" do
    it "returns nil when SMTP is not configured" do
      expect(build(:alert_setting, smtp_address: nil).smtp_settings).to be_nil
    end

    it "builds the ActionMailer hash from the configured fields" do
      settings = build(:alert_setting).smtp_settings
      expect(settings).to eq(
        address: "smtp.example.com",
        port: 587,
        user_name: "alerts",
        password: "secret",
        authentication: :plain
      )
    end
  end

  describe "#from_address" do
    it "falls back to the default sender" do
      expect(build(:alert_setting, smtp_from: nil).from_address).to eq("alerts@deepdiver.local")
      expect(build(:alert_setting, smtp_from: "ops@example.com").from_address).to eq("ops@example.com")
    end
  end
end
