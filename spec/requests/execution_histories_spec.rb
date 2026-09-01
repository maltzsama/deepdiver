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

  it "lists open freshness breaches with triage state in the merged list" do
    check
    freshness_event

    get execution_histories_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("unassigned")
    expect(response.body).to include(">Open<")
  end

  it "acknowledges a freshness event from the merged history" do
    event = freshness_event

    patch acknowledge_execution_history_path(event.id)

    expect(event.reload.status).to eq("acknowledged")
    expect(response).to redirect_to(execution_histories_path)
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

RSpec.describe "Execution histories merged timeline", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it "interleaves maintenance and freshness rows chronologically in one list" do
    create(:execution_history, iceberg_table: create(:iceberg_table), status: "success",
                               started_at: 2.hours.ago)
    create(:freshness_check, iceberg_table: create(:iceberg_table), status: "late",
                             checked_at: 1.hour.ago)

    get execution_histories_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("maintenance")
    expect(response.body).to include("freshness")
  end

  it "filters the merged list by kind" do
    create(:execution_history, iceberg_table: create(:iceberg_table), status: "success",
                               started_at: 2.hours.ago)
    create(:freshness_check, iceberg_table: create(:iceberg_table), status: "late",
                             checked_at: 1.hour.ago)

    get execution_histories_path(kind: "maintenance")

    expect(response.body).to include("maintenance")
    # The freshness check article carries the freshness kind badge; filtered
    # out, it must not render.
    expect(response.body).not_to include("op-run\">\n      <span class=\"badge badge-mute flex-none\">freshness")
  end

  it "round-trips the kind filter on submit" do
    create(:freshness_check, iceberg_table: create(:iceberg_table), status: "late",
                             checked_at: 1.hour.ago)

    get execution_histories_path, params: { kind: "freshness", status: "late" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("selected")
    expect(response.body).to include("freshness")
  end
end
