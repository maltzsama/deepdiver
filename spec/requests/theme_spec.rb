require "rails_helper"

RSpec.describe "Theme toggle", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "defaults the html data-theme to dark" do
    get root_path

    expect(response.body).to match(/<html[^>]*data-theme="dark"/)
  end

  it "toggles to light and persists it in a cookie" do
    post toggle_theme_path

    expect(response).to redirect_to(root_path)
    expect(response.cookies["theme"]).to eq("light")

    get root_path
    expect(response.body).to match(/<html[^>]*data-theme="light"/)
  end

  it "toggles back to dark when already light" do
    cookies[:theme] = "light"

    post toggle_theme_path

    expect(response.cookies["theme"]).to eq("dark")
  end

  it "honours an explicit theme param" do
    post toggle_theme_path, params: { theme: "light" }
    expect(response.cookies["theme"]).to eq("light")

    post toggle_theme_path, params: { theme: "dark" }
    expect(response.cookies["theme"]).to eq("dark")
  end
end
