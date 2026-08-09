require "test_helper"

class PermissionsIntegrationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(email: "admin@example.com", password: "password", role: "admin")
    @viewer = User.create!(email: "viewer@example.com", password: "password", role: "viewer")
  end

  test "unauthenticated users are redirected to sign in" do
    get "/"
    assert_redirected_to new_user_session_path
  end

  test "viewers can browse the read-only pages" do
    sign_in @viewer
    get "/catalogs"
    assert_response :success
    get "/maintenance_schedules"
    assert_response :success
  end

  test "viewers cannot mutate catalogs" do
    sign_in @viewer
    assert_no_difference("Catalog.count") do
      post "/catalogs", params: { catalog: { name: "x", catalog_type: "nessie", endpoint: "http://x" } }
    end
    assert_redirected_to root_path
  end

  test "admins can create catalogs with JSON properties" do
    sign_in @admin
    assert_difference("Catalog.count", 1) do
      post "/catalogs", params: {
        catalog: { name: "ods", catalog_type: "nessie", endpoint: "http://nessie:19120",
                   trino_catalog_name: "ods", properties: "{}" }
      }
    end
    assert_response :redirect
  end
end
