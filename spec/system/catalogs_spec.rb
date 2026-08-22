require "rails_helper"

RSpec.describe "Catalogs", type: :system do
  let!(:admin) { create(:user, :admin, email: "admin@test.com", password: "password123") }

  before do
    login_as(admin, scope: :user)
  end

  it "lists catalogs" do
    create(:catalog, name: "test_catalog")
    visit catalogs_path
    expect(page).to have_content("test_catalog")
  end

  it "creates a catalog" do
    visit catalogs_path
    click_link "New catalog"
    fill_in "Name", with: "new_catalog"
    fill_in "Endpoint", with: "https://polaris.example.com"
    click_button "Save catalog"
    expect(page).to have_content("new_catalog")
  end
end
