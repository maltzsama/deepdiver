require "rails_helper"

RSpec.describe "Authentication", type: :system do
  let!(:admin) { create(:user, :admin, email: "admin@test.com", password: "password123") }

  it "signs in with email and password" do
    visit new_user_session_path
    fill_in "Email", with: admin.email
    fill_in "Password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path(root_path)
  end

  it "rejects invalid credentials" do
    visit new_user_session_path
    fill_in "Email", with: admin.email
    fill_in "Password", with: "wrong"
    click_button "Sign in"
    expect(page).to have_content("Invalid")
  end

  it "signs out" do
    login_as(admin, scope: :user)
    visit root_path
    find("button[aria-label='Profile']").click
    click_button "Sign out"
    expect(page).to have_current_path(new_user_session_path)
  end
end
