require "rails_helper"

RSpec.describe TableFreshnessSla, type: :model do
  describe "severity band validations" do
    it "defaults to the 3h/6h/12h bands" do
      sla = build(:table_freshness_sla)

      expect(sla.warning_after_minutes).to eq(180)
      expect(sla.severe_after_minutes).to eq(360)
      expect(sla.critical_after_minutes).to eq(720)
    end

    it "requires positive bands" do
      expect(build(:table_freshness_sla, warning_after_minutes: 0)).not_to be_valid
      expect(build(:table_freshness_sla, severe_after_minutes: -1)).not_to be_valid
    end

    it "rejects bands that are not ordered" do
      expect(build(:table_freshness_sla, severe_after_minutes: 180, critical_after_minutes: 720)).not_to be_valid
      expect(build(:table_freshness_sla, warning_after_minutes: 720, severe_after_minutes: 360, critical_after_minutes: 720)).not_to be_valid
    end

    it "accepts custom ordered bands" do
      expect(build(:table_freshness_sla,
                   warning_after_minutes: 60, severe_after_minutes: 120, critical_after_minutes: 240)).to be_valid
    end
  end

  describe "#alert_configured?" do
    it "is true when a Slack channel is set" do
      expect(build(:table_freshness_sla, slack_channel: "#support", email_to: nil)).to be_alert_configured
    end

    it "is true when an email is set" do
      expect(build(:table_freshness_sla, slack_channel: nil, email_to: "support@example.com")).to be_alert_configured
    end

    it "is false when neither is set" do
      expect(build(:table_freshness_sla, slack_channel: nil, email_to: nil)).not_to be_alert_configured
    end
  end
end
