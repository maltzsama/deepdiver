require "rails_helper"

RSpec.describe "GET /execution_histories", type: :request do
  let(:user)    { create(:user) }
  let(:catalog) { create(:catalog) }
  let(:other)   { create(:catalog, name: "legacy") }

  let(:table)        { create(:iceberg_table, catalog:, name: "sales") }
  let(:other_table)  { create(:iceberg_table, catalog: other, name: "orders") }

  let(:optimize) { create(:maintenance_schedule, iceberg_table: table, operation: "optimize") }
  let(:expire)   { create(:maintenance_schedule, iceberg_table: table, operation: "expire_snapshots") }
  let(:foreign)  { create(:maintenance_schedule, iceberg_table: other_table, operation: "optimize") }

  let!(:failed_execution) do
    optimize.execution_histories.create!(status: :failed, current_step: :done, error_message: "commit conflict")
  end
  let!(:success_execution) do
    expire.execution_histories.create!(status: :success, current_step: :done)
  end
  let!(:foreign_execution) do
    foreign.execution_histories.create!(status: :success, current_step: :done)
  end

  before do
    failed_execution.execution_steps.create!(operation: "optimize", status: "failed",
                                             error_message: "commit conflict")
    success_execution.execution_steps.create!(operation: "expire_snapshots", status: "succeeded")
    sign_in user
  end

  it "lists executions, most recent first" do
    get execution_histories_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("sales")
  end

  it "filters by status" do
    get execution_histories_path, params: { status: "failed" }

    expect(response.body).to include("commit conflict")
    expect(response.body).not_to include("orders")
  end

  it "filters by chain step operation" do
    get execution_histories_path, params: { operation: "expire_snapshots" }

    expect(response.body).to include("sales")
    expect(response.body).not_to include("commit conflict")
  end

  it "filters by catalog" do
    get execution_histories_path, params: { catalog_id: other.id }

    expect(response.body).to include("orders")
    expect(response.body).not_to include("sales")
  end

  it "filters by the step where the execution stopped" do
    get execution_histories_path, params: { stopped_at_step: "optimize" }

    expect(response.body).to include("commit conflict")
    expect(response.body).not_to include("orders")
  end

  it "shows the full error message, not truncated" do
    get execution_histories_path

    expect(response.body).to include("commit conflict")
  end
end

RSpec.describe "GET /execution_histories (unified feed)", type: :request do
  let(:user)   { create(:user) }
  let(:table)  { create(:iceberg_table) }

  before { sign_in user }

  it "interleaves maintenance and freshness by time, most recent first" do
    plan = create(:maintenance_plan, iceberg_table: table)
    create(:execution_history, maintenance_plan: plan, iceberg_table: table,
                               started_at: 2.hours.ago, status: :success)
    create(:freshness_check, iceberg_table: table, checked_at: 1.hour.ago, status: "late")

    get execution_histories_path

    events = assigns(:events)
    expect(events.map { |e| e[:kind] }).to eq(%i[freshness maintenance])
  end

  it "filters to freshness only when asked" do
    plan = create(:maintenance_plan, iceberg_table: table)
    create(:execution_history, maintenance_plan: plan, iceberg_table: table, started_at: 1.hour.ago)
    create(:freshness_check, iceberg_table: table, checked_at: 30.minutes.ago, status: "ok")

    get execution_histories_path, params: { kind: "freshness" }

    expect(assigns(:events).map { |e| e[:kind] }.uniq).to eq([ :freshness ])
  end

  it "maps a maintenance status filter onto the closest freshness status" do
    create(:freshness_check, iceberg_table: table, status: "error")
    create(:freshness_check, iceberg_table: table, status: "ok")

    get execution_histories_path, params: { status: "failed" }

    statuses = assigns(:events).select { |e| e[:kind] == :freshness }.map { |e| e[:record].status }
    expect(statuses).to eq([ "error" ])
  end
end
