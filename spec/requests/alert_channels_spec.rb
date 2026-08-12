require "rails_helper"

RSpec.describe "AlertChannels", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:viewer) { create(:user, role: "viewer") }

  describe "authorization" do
    it "lets an admin manage channels" do
      sign_in admin
      get alert_channels_path

      expect(response).to have_http_status(:ok)
    end

    it "does not let a viewer manage channels" do
      sign_in viewer
      get alert_channels_path
      follow_redirect!

      expect(response.body).to include("You do not have permission")
    end
  end

  describe "POST /alert_channels" do
    before { sign_in admin }

    it "creates a slack channel" do
      expect {
        post alert_channels_path,
             params: { alert_channel: { name: "Support", slack_channel: "#support", email_to: "", min_severity: "warning" } }
      }.to change(AlertChannel, :count).by(1)

      expect(AlertChannel.last).to have_attributes(name: "Support", slack_channel: "#support")
    end

    it "rejects a channel with no destination" do
      expect {
        post alert_channels_path,
             params: { alert_channel: { name: "Void", slack_channel: "", email_to: "" } }
      }.not_to change(AlertChannel, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /alert_channels/:id" do
    before { sign_in admin }
    let(:channel) { create(:alert_channel, :slack) }

    it "updates the channel" do
      patch alert_channel_path(channel), params: { alert_channel: { email_to: "ops@example.com" } }

      expect(channel.reload.email_to).to eq("ops@example.com")
    end
  end

  describe "DELETE /alert_channels/:id" do
    before { sign_in admin }

    it "destroys the channel" do
      channel = create(:alert_channel, :slack)

      expect {
        delete alert_channel_path(channel)
      }.to change(AlertChannel, :count).by(-1)
    end
  end

  describe "POST /alert_channels/:id/test" do
    before { sign_in admin }
    let(:channel) { create(:alert_channel, :slack) }
    let!(:alert_setting) { create(:alert_setting) }

    it "delivers a test alert through the channel" do
      allow(SlackAlert).to receive(:notify)

      post test_alert_channel_path(channel)

      expect(SlackAlert).to have_received(:notify)
      expect(response).to redirect_to(alert_channels_path)
    end
  end
end
