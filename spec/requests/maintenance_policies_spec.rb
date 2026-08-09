require "rails_helper"

RSpec.describe "MaintenancePolicies", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:viewer) { create(:user, role: "viewer") }
  let(:policy) do
    MaintenancePolicy.create!(name: "P", operation: "optimize", cron: "0 3 * * *")
  end

  describe "authorization" do
    it "lets a viewer see the list" do
      sign_in viewer
      get maintenance_policies_path

      expect(response).to have_http_status(:ok)
    end

    it "does not let a viewer create a policy" do
      sign_in viewer

      expect {
        post maintenance_policies_path,
             params: { maintenance_policy: { name: "N", operation: "optimize", cron: "0 3 * * *" } }
      }.not_to change(MaintenancePolicy, :count)
    end

    it "does not let a viewer apply a policy" do
      sign_in viewer
      table = create(:iceberg_table)

      expect {
        post apply_maintenance_policy_path(policy), params: { iceberg_table_ids: [ table.id ] }
      }.not_to change(MaintenanceSchedule, :count)
    end
  end

  describe "POST /maintenance_policies/:id/apply" do
    before { sign_in admin }

    it "applies to the selected tables and reports the result" do
      tables = create_list(:iceberg_table, 2)

      post apply_maintenance_policy_path(policy),
           params: { iceberg_table_ids: tables.map(&:id) }

      expect(MaintenanceSchedule.count).to eq(2)
      follow_redirect!
      expect(response.body).to include("2 schedule(s) created")
    end

    it "ignores blank ids coming from the form" do
      table = create(:iceberg_table)

      post apply_maintenance_policy_path(policy),
           params: { iceberg_table_ids: [ "", table.id.to_s ] }

      expect(MaintenanceSchedule.count).to eq(1)
    end
  end
end
