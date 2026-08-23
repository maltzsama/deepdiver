require "rails_helper"

RSpec.describe "GET /users/sign_in", type: :request do
  it "renders without the application header" do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("auth-shell")
    expect(response.body).not_to include("app-headbar")
  end

  it "does not offer a sign-up link" do
    get new_user_session_path

    expect(response.body).not_to include("sign_up")
  end

  it "uses translations and not raw text" do
    get new_user_session_path

    expect(response.body).to include(I18n.t("auth.sign_in.title"))
    expect(response.body).not_to include("translation missing")
  end
end
