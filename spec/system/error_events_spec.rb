require "rails_helper"

RSpec.describe "Error Events", type: :system do
  let!(:admin) { create(:user, :admin, email: "admin@test.com", password: "password123") }

  before do
    login_as(admin, scope: :user)
  end

  it "lists error events" do
    create(:error_event, operation: "test-op", schema: "test")
    visit error_events_path
    expect(page).to have_content("test-op")
  end
end
