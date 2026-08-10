require "rails_helper"

RSpec.describe "Public registration", type: :request do
  it "does not expose the sign-up route" do
    get "/users/sign_up"

    expect(response).to have_http_status(:not_found)
  end

  it "does not accept account creation via POST" do
    post "/users", params: { user: { email: "intruder@example.com", password: "password123" } }

    expect(response).to have_http_status(:found)
    expect(User.find_by(email: "intruder@example.com")).to be_nil
  end

  it "keeps self-account editing for signed-in users" do
    sign_in create(:user)
    get edit_user_registration_path

    expect(response).to have_http_status(:ok)
  end
end
