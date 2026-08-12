require "rails_helper"

RSpec.describe AlertChannel, type: :model do
  describe "validations" do
    it "requires a name" do
      expect(build(:alert_channel, name: nil)).not_to be_valid
    end

    it "requires a destination (Slack, Email, or both)" do
      expect(build(:alert_channel, slack_channel: nil, email_to: nil)).not_to be_valid
      expect(build(:alert_channel, :slack)).to be_valid
      expect(build(:alert_channel, :email)).to be_valid
      expect(build(:alert_channel, :slack_and_email)).to be_valid
    end

    it "validates min_severity is one of the known levels" do
      expect(build(:alert_channel, min_severity: "pagerduty")).not_to be_valid
    end

    it "validates cooldown_minutes is a non-negative integer" do
      expect(build(:alert_channel, cooldown_minutes: -1)).not_to be_valid
      expect(build(:alert_channel, cooldown_minutes: 0)).to be_valid
    end
  end

  describe "#receives?" do
    let(:warning) { build(:alert_channel, min_severity: "warning") }
    let(:severe)  { build(:alert_channel, min_severity: "severe") }
    let(:critical) { build(:alert_channel, min_severity: "critical") }

    it "passes alerts at or above the minimum severity" do
      expect(warning.receives?("warning")).to be(true)
      expect(warning.receives?("critical")).to be(true)
      expect(severe.receives?("severe")).to be(true)
      expect(severe.receives?("critical")).to be(true)
      expect(critical.receives?("critical")).to be(true)
    end

    it "filters out alerts below the minimum severity" do
      expect(severe.receives?("warning")).to be(false)
      expect(critical.receives?("warning")).to be(false)
      expect(critical.receives?("severe")).to be(false)
    end
  end

  describe "#cooling_down?" do
    it "is false when never sent" do
      expect(build(:alert_channel, last_sent_at: nil)).not_to be_cooling_down
    end

    it "is true inside the cooldown window" do
      channel = create(:alert_channel, cooldown_minutes: 60, last_sent_at: 10.minutes.ago)
      expect(channel).to be_cooling_down
    end

    it "is false after the cooldown window" do
      channel = create(:alert_channel, cooldown_minutes: 60, last_sent_at: 2.hours.ago)
      expect(channel).not_to be_cooling_down
    end
  end

  describe "scopes" do
    it "only returns enabled channels" do
      enabled = create(:alert_channel, :slack, enabled: true)
      create(:alert_channel, :slack, enabled: false)

      expect(described_class.enabled).to contain_exactly(enabled)
    end
  end
end
