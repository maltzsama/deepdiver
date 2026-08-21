require "rails_helper"

RSpec.describe "Profile", type: :request do
  let(:user) { create(:user) }

  describe "GET /profile" do
    before { sign_in user }

    it "shows the profile" do
      get profile_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Profile")
    end

    it "does not expose the password form to SSO accounts" do
      sso_user = create(:user, :sso)
      sign_in sso_user
      get profile_path

      expect(response.body).not_to include("current_password")
    end
  end

  describe "PATCH /profile" do
    before { sign_in user }

    it "updates display name, locale and theme" do
      patch profile_path, params: { user: { display_name: "D. Albuquerque", locale: "en", theme: "dark" } }

      expect(response).to redirect_to(profile_path)
      user.reload
      expect(user.display_name).to eq("D. Albuquerque")
      expect(user.locale).to eq("en")
      expect(user.theme).to eq("dark")
      expect(user.role).to eq("viewer")
    end

    it "never lets the caller promote themselves" do
      patch profile_path, params: { user: { display_name: "Hacker", role: "admin" } }

      expect(user.reload.role).to eq("viewer")
    end
  end

  describe "PATCH /profile/password" do
    before { sign_in user }

    it "changes the password with the current password" do
      patch password_profile_path, params: {
        user: { current_password: user.password, password: "new-secret-123", password_confirmation: "new-secret-123" }
      }

      expect(response).to redirect_to(profile_path)
      expect(user.reload.valid_password?("new-secret-123")).to be true
    end

    it "rejects a wrong current password" do
      patch password_profile_path, params: {
        user: { current_password: "nope", password: "new-secret-123", password_confirmation: "new-secret-123" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.valid_password?("new-secret-123")).to be false
    end

    it "does not let SSO accounts change the password" do
      sso_user = create(:user, :sso)
      sign_in sso_user

      patch password_profile_path, params: {
        user: { current_password: sso_user.password, password: "new-secret-123", password_confirmation: "new-secret-123" }
      }

      expect(response).to have_http_status(:not_found)
    end
  end
end
