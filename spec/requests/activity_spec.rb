require "rails_helper"

RSpec.describe "GET /activity", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "renders the engine state and running executions" do
    plan = create(:maintenance_plan, :with_all_steps)
    execution = create(:execution_history, maintenance_plan: plan, iceberg_table: plan.iceberg_table,
                                           status: :running, current_step: "optimize")
    TrinoEngineSupervisor.state.update!(status: "up", status_changed_at: Time.current)

    get activity_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(execution.iceberg_table.fully_qualified_name)
    expect(response.body).to include("Up for")
  end

  it "lists queued executions with their wait reason" do
    plan = create(:maintenance_plan, :with_all_steps)
    create(:execution_history, maintenance_plan: plan, iceberg_table: plan.iceberg_table, status: :pending)

    get activity_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("waiting for the engine")
  end
end
