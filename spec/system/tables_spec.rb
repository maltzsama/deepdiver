require "rails_helper"

RSpec.describe "Tables", type: :system do
  let!(:admin) { create(:user, :admin, email: "admin@test.com", password: "password123") }
  let!(:catalog) { create(:catalog, name: "test_catalog") }

  before do
    login_as(admin, scope: :user)
  end

  it "lists tables" do
    create(:iceberg_table, catalog: catalog, name: "my_table", namespace: "public")
    visit iceberg_tables_path
    expect(page).to have_content("public.my_table")
  end
end
