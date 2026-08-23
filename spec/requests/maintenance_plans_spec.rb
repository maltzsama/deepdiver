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

    it "resume zeros the consecutive-failure counter" do
      plan.update!(is_paused: true, consecutive_failures: 3, needs_review: true)

      post resume_maintenance_plan_path(plan)

      expect(plan.reload.consecutive_failures).to eq(0)
      expect(plan.reload.needs_review).to be false
    end
  end

  describe "PATCH /maintenance_plans/:id" do
    before { sign_in admin }

    it "updates the cron" do
      patch maintenance_plan_path(plan),
            params: { maintenance_plan: { cron: "0 6 * * 1" } }

      expect(response).to redirect_to(plan)
      expect(plan.reload.cron).to eq("0 6 * * 1")
    end

    it "disables a step without deleting it" do
      step = plan.maintenance_steps.find_by!(operation: "remove_orphan_files")

      patch maintenance_plan_path(plan), params: {
        maintenance_plan: {
          maintenance_steps_attributes: {
            "0" => { id: step.id, enabled: "0" }
          }
        }
      }

      expect(response).to redirect_to(plan)
      expect(plan.reload.maintenance_steps.count).to eq(4)
      expect(step.reload.enabled).to be false
    end

    it "rejects an invalid cron" do
      patch maintenance_plan_path(plan),
            params: { maintenance_plan: { cron: "not-a-cron" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(plan.reload.cron).not_to eq("not-a-cron")
    end

    it "rejects a cadence that never coincides with the plan" do
      patch maintenance_plan_path(plan), params: {
        maintenance_plan: {
          cron: plan.cron,
          maintenance_steps_attributes: {
            "0" => {
              id: plan.maintenance_steps.first.id,
              cadence_cron: "30 3 * * *"
            }
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "blocks viewers" do
      viewer = create(:user)
      sign_in viewer

      patch maintenance_plan_path(plan), params: { maintenance_plan: { cron: "0 6 * * 1" } }

      expect(response).to redirect_to(root_path)
      expect(plan.reload.cron).not_to eq("0 6 * * 1")
    end
  end

  describe "GET /maintenance_plans/:id/edit" do
    before { sign_in admin }

    it "shows all four canonical steps" do
      get edit_maintenance_plan_path(plan)

      expect(response).to have_http_status(:ok)
      MaintenancePlan::CANONICAL_ORDER.each do |operation|
        expect(response.body).to include(operation)
      end
    end

    it "blocks viewers" do
      viewer = create(:user)
      sign_in viewer

      get edit_maintenance_plan_path(plan)

      expect(response).to redirect_to(root_path)
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
