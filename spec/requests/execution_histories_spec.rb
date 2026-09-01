require "rails_helper"

RSpec.describe "Execution histories freshness triage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:table) { create(:iceberg_table) }
  let(:check) do
    create(:freshness_check, iceberg_table: table, status: "late",
                             delay_seconds: 300, checked_at: Time.current)
  end

  before { sign_in admin }

  def freshness_event
    ErrorEvent.record_freshness_late!(table: table, context: { delay: "5 min", sla_minutes: 1 })
  end

  it "lists open freshness breaches with triage state on the freshness tab" do
    check
    freshness_event

    get execution_histories_path(tab: "freshness")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("unassigned")
    expect(response.body).to include(">Open<")
  end

  it "acknowledges a freshness event from the history tab" do
    event = freshness_event

    patch acknowledge_execution_history_path(event.id)

    expect(event.reload.status).to eq("acknowledged")
    expect(response).to redirect_to(execution_histories_path(tab: "freshness"))
  end

  it "assigns a freshness event to a user" do
    event = freshness_event
    operator = create(:user, :operator)

    patch assign_execution_history_path(event.id), params: { target_type: "user", target_id: operator.id }

    expect(event.reload.assigned_to).to eq(operator)
  end

  it "resolves an acknowledged freshness event" do
    event = freshness_event
    event.update!(status: "acknowledged", acknowledged_at: Time.current)

    patch resolve_execution_history_path(event.id)

    expect(event.reload).to be_resolved
  end

  it "does not expose the triage actions to viewers" do
    viewer = create(:user)
    sign_in viewer
    event = freshness_event

    patch acknowledge_execution_history_path(event.id)

    expect(response).to redirect_to(root_path)
    expect(event.reload.status).to eq("open")
  end
end
