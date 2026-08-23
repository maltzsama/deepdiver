require "rails_helper"

RSpec.describe "AlertSettings", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:viewer) { create(:user, role: "viewer") }

  describe "authorization" do
    it "lets an admin edit settings" do
      sign_in admin
      get alert_settings_path

      expect(response).to have_http_status(:ok)
    end

    it "does not let a viewer edit settings" do
      sign_in viewer
      get alert_settings_path
      follow_redirect!

      expect(response.body).to include("You do not have permission")
    end
  end

  describe "PATCH /alert_settings" do
    before { sign_in admin }

    it "updates the singleton settings" do
      patch alert_settings_path,
            params: { alert_setting: { smtp_address: "smtp.ops.example.com", smtp_port: 465 } }

      expect(AlertSetting.instance.reload).to have_attributes(
        smtp_address: "smtp.ops.example.com",
        smtp_port: 465
      )
    end
  end
end
