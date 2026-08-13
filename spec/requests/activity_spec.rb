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

  it "lets an admin cancel a running execution" do
    sign_in create(:user, :admin)
    plan = create(:maintenance_plan, :with_all_steps)
    execution = create(:execution_history, maintenance_plan: plan, iceberg_table: plan.iceberg_table,
                                           status: :running)
    TrinoEngineSupervisor.state.update!(status: "up", status_changed_at: Time.current)

    post cancel_execution_history_path(execution)

    expect(response).to redirect_to(activity_path)
    expect(execution.reload.status).to eq("failed")
    expect(execution.error_message).to include("cancelled by operator")
    expect(TrinoEngineSupervisor.state.reload.status).to eq("draining")
  end

  it "marks a cancelled queued execution as skipped" do
    sign_in create(:user, :admin)
    plan = create(:maintenance_plan, :with_all_steps)
    execution = create(:execution_history, maintenance_plan: plan, iceberg_table: plan.iceberg_table,
                                           status: :pending)

    post cancel_execution_history_path(execution)

    expect(execution.reload.status).to eq("skipped")
    expect(execution.error_message).to include("cancelled by operator")
  end

  it "lets an operator cancel a queued execution" do
    sign_in create(:user, :operator)
    plan = create(:maintenance_plan, :with_all_steps)
    execution = create(:execution_history, maintenance_plan: plan, iceberg_table: plan.iceberg_table,
                                           status: :pending)

    post cancel_execution_history_path(execution)

    expect(execution.reload.status).to eq("skipped")
  end

  it "lets an operator cancel a trino query" do
    sign_in create(:user, :operator)
    TrinoProvisioner.adapter = FakeTrinoProvisioner.new
    allow(TrinoProvisioner).to receive(:cancel_query).and_return(true)

    post cancel_trino_query_activity_path(query_id: "20260813_000000_00000_abcde")

    expect(response).to redirect_to(activity_path)
    expect(TrinoProvisioner).to have_received(:cancel_query).with("20260813_000000_00000_abcde")
  end

  it "does not let a viewer cancel a trino query" do
    sign_in create(:user, role: "viewer")

    post cancel_trino_query_activity_path(query_id: "qid")

    expect(response).to redirect_to(root_path)
  end
end
