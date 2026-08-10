require "test_helper"

class PermissionsIntegrationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(email: "admin@example.com", password: "password", role: "admin")
    @viewer = User.create!(email: "viewer@example.com", password: "password", role: "viewer")
    @catalog = build_catalog
    @table = @catalog.iceberg_tables.create!(namespace: "reporting", name: "dwd_orders")
    @plan = MaintenancePlan.create!(iceberg_table: @table, cron: "0 3 * * *")
    @plan.maintenance_steps.create!(operation: "optimize", position: 0, config: {})
    @policy = MaintenancePolicy.create!(name: "Nightly Compaction", cron: "0 3 * * *", steps_config: { "optimize" => {} })
    @execution = @plan.execution_histories.create!(status: :running, current_step: :start, iceberg_table_id: @table.id)
    @schedule = @table.maintenance_schedules.create!(operation: "optimize", cron: "0 3 * * *")
  end

  test "unauthenticated users are redirected to sign in" do
    get "/"
    assert_redirected_to new_user_session_path
  end

  test "viewers can browse the read-only pages" do
    sign_in @viewer
    get "/"
    assert_response :success
    get "/catalogs"
    assert_response :success
    get "/iceberg_tables"
    assert_response :success
    get "/iceberg_tables/#{@table.id}"
    assert_response :success
    get "/maintenance_plans"
    assert_response :success
    get "/maintenance_plans/#{@plan.id}"
    assert_response :success
    get "/maintenance_policies"
    assert_response :success
    get "/maintenance_policies/#{@policy.id}"
    assert_response :success
    get "/maintenance_schedules"
    assert_response :success
    get "/maintenance_schedules/#{@schedule.id}"
    assert_response :success
    get "/execution_histories"
    assert_response :success
    get "/activity"
    assert_response :success
  end

  test "viewers cannot mutate catalogs" do
    sign_in @viewer
    assert_no_difference("Catalog.count") do
      post "/catalogs", params: { catalog: { name: "x", catalog_type: "nessie", endpoint: "http://x" } }
    end
    assert_redirected_to root_path
  end

  test "viewers cannot run or manage maintenance" do
    sign_in @viewer

    assert_no_difference("ExecutionHistory.count") do
      post "/iceberg_tables/#{@table.id}/run_maintenance"
    end
    assert_redirected_to root_path

    assert_no_difference("ExecutionHistory.count") do
      post "/maintenance_plans/#{@plan.id}/run"
    end
    assert_redirected_to root_path

    post "/maintenance_plans/#{@plan.id}/pause"
    assert_redirected_to root_path
    assert_not @plan.reload.is_paused

    post "/maintenance_plans/#{@plan.id}/resume"
    assert_redirected_to root_path
  end

  test "viewers cannot create or apply maintenance policies" do
    sign_in @viewer

    assert_no_difference("MaintenancePolicy.count") do
      post "/maintenance_policies", params: { maintenance_policy: { name: "x", cron: "0 3 * * *" } }
    end
    assert_redirected_to root_path

    assert_no_difference("MaintenancePlan.count") do
      post "/maintenance_policies/#{@policy.id}/apply", params: { iceberg_table_ids: [ @table.id.to_s ] }
    end
    assert_redirected_to root_path
  end

  test "viewers cannot cancel executions" do
    sign_in @viewer

    post "/execution_histories/#{@execution.id}/cancel"
    assert_redirected_to root_path
    assert_equal "running", @execution.reload.status
  end

  test "viewers cannot create or destroy maintenance schedules" do
    sign_in @viewer

    assert_no_difference("MaintenanceSchedule.count") do
      post "/maintenance_schedules", params: {
        maintenance_schedule: { iceberg_table_id: @table.id, operation: "optimize", cron: "0 3 * * *" }
      }
    end
    assert_redirected_to root_path

    assert_no_difference("MaintenanceSchedule.count") do
      delete "/maintenance_schedules/#{@schedule.id}"
    end
    assert_redirected_to root_path
  end

  test "viewers cannot restart the engine" do
    sign_in @viewer

    post "/activity/restart"
    assert_redirected_to root_path
  end

  test "admins can mutate catalogs with JSON properties" do
    sign_in @admin
    assert_difference("Catalog.count", 1) do
      post "/catalogs", params: {
        catalog: { name: "ods", catalog_type: "nessie", endpoint: "http://nessie:19120" }
      }
    end
    assert_response :redirect
  end

  test "admins can pause and resume plans" do
    sign_in @admin

    post "/maintenance_plans/#{@plan.id}/pause"
    assert_response :redirect
    assert @plan.reload.is_paused

    post "/maintenance_plans/#{@plan.id}/resume"
    assert_response :redirect
    assert_not @plan.reload.is_paused
  end

  test "admins can cancel executions" do
    sign_in @admin

    post "/execution_histories/#{@execution.id}/cancel"
    assert_response :redirect
    assert_equal "failed", @execution.reload.status
  end

  test "admins can create maintenance schedules" do
    sign_in @admin

    assert_difference("MaintenanceSchedule.count", 1) do
      post "/maintenance_schedules", params: {
        maintenance_schedule: { iceberg_table_id: @table.id, operation: "expire_snapshots", cron: "0 3 * * *" }
      }
    end
    assert_response :redirect
  end

  test "admins can restart the engine" do
    sign_in @admin

    post "/activity/restart"
    assert_response :redirect
    assert_equal "starting", TrinoEngineState.last.status
  end
end
