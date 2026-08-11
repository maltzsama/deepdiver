require "rails_helper"

RSpec.describe "Auth smoke", type: :request do
  it "renders the login page with the new auth layout" do
    get new_user_session_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("auth-brand")
    expect(response.body).to include("auth-logo-box")
    expect(response.body).to include("auth-version")
    expect(response.body).not_to include("auth-strata")
  end

  it "renders the profile dropdown with profile and sign out" do
    user = create(:user)
    sign_in user
    get root_path
    expect(response.body).to include("data-controller=\"dropdown\"")
    expect(response.body).to include('action="/users/sign_out"')
    expect(response.body).to include("Sign out")
    expect(response.body).to include("topbar-btn-avatar")
  end
end
