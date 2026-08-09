require "rails_helper"

RSpec.describe "MaintenancePlans", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:plan) { create(:maintenance_plan, :with_all_steps) }

  describe "GET /maintenance_plans" do
    it "lists plans" do
      sign_in create(:user)
      get maintenance_plans_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /maintenance_plans/:id/pause and resume" do
    before { sign_in admin }

    it "pauses and resumes the plan" do
      post pause_maintenance_plan_path(plan)
      expect(plan.reload.is_paused).to be true

      post resume_maintenance_plan_path(plan)
      expect(plan.reload.is_paused).to be false
    end
  end

  describe "POST /maintenance_plans/:id/run" do
    before { sign_in admin }

    it "enqueues a run" do
      expect { post run_maintenance_plan_path(plan) }
        .to change(plan.execution_histories, :count).by(1)
    end
  end
end
