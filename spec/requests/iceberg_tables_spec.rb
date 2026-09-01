require "rails_helper"

RSpec.describe "GET /iceberg_tables", type: :request do
  let(:user)     { create(:user) }
  let(:catalog)  { create(:catalog, name: "polaris_prod") }
  let(:other)    { create(:catalog, name: "legacy_nessie") }

  let!(:critical_table) do
    create(:iceberg_table, catalog:, namespace: "bronze", name: "sales",
                           health_status: "critical", health_score: 10)
  end
  let!(:healthy_table) do
    create(:iceberg_table, catalog:, namespace: "silver", name: "customers",
                           health_status: "healthy", health_score: 95)
  end
  let!(:other_catalog_table) do
    create(:iceberg_table, catalog: other, namespace: "bronze", name: "orders",
                           health_status: "warning", health_score: 50)
  end

  before { sign_in user }

  it "lists everything, worst score first" do
    get iceberg_tables_path

    expect(response.body.index("sales")).to be < response.body.index("customers")
  end

  it "filters by catalog" do
    get iceberg_tables_path, params: { catalog_id: catalog.id }

    expect(response.body).to include("sales")
    expect(response.body).not_to include("orders")
  end

  it "filters by health status" do
    get iceberg_tables_path, params: { health_status: "critical" }

    expect(response.body).to include("sales")
    expect(response.body).not_to include("customers")
  end

  it "filters by namespace" do
    get iceberg_tables_path, params: { namespace: "silver" }

    expect(response.body).to include("customers")
    expect(response.body).not_to include("sales")
  end

  it "searches by name without case sensitivity" do
    get iceberg_tables_path, params: { q: "SAL" }

    expect(response.body).to include("sales")
    expect(response.body).not_to include("customers")
  end

  it "combines filters" do
    get iceberg_tables_path, params: { catalog_id: catalog.id, health_status: "healthy" }

    expect(response.body).to include("customers")
    expect(response.body).not_to include("sales")
  end

  it "flags tables without a plan" do
    get iceberg_tables_path

    expect(response.body).to include("+ plan")
  end

  it "wraps the action buttons in a flex container so they align side by side" do
    sign_in create(:user, :admin)
    get iceberg_tables_path

    expect(response.body).to match(%r{<span class="inline-flex items-center gap-2">})
  end

  it "filters by tables without a plan" do
    create(:maintenance_plan, :with_all_steps, iceberg_table: critical_table)

    get iceberg_tables_path, params: { no_plan: "1" }

    expect(response.body).to include("customers")
    expect(response.body).not_to include("sales")
  end

  it "shows the table count as a number, not a grouped hash" do
    get iceberg_tables_path

    expect(response.body).to include("3 table(s)")
    expect(response.body).not_to match(/\{\d+ =>/)
  end

  it "hides inactive tables by default" do
    critical_table.deactivate!

    get iceberg_tables_path

    expect(response.body).not_to include("sales")
    expect(response.body).to include("customers")
  end

  it "includes inactive tables when the operator asks for them" do
    critical_table.deactivate!

    get iceberg_tables_path, params: { inactive: "1" }

    expect(response.body).to include("sales")
    expect(response.body).to include("inactive")
  end
end

RSpec.describe "GET /iceberg_tables/:id", type: :request do
  let(:user)     { create(:user) }
  let(:catalog)  { create(:catalog) }

  before { sign_in user }

  it "explains the health score component by component" do
    table = create(:iceberg_table, catalog:, snapshot_count: 120,
                   total_size_bytes: 2_000_000_000, total_data_files: 200,
                   total_records: 10_000_000, health_score: 62, health_status: "warning")

    get iceberg_table_path(table)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Maintenance health")
    expect(response.body).to include("Fragmentation")
    expect(response.body).to include("Snapshots")
    expect(response.body).to include("no data")
  end

  it "says when there is not enough data to score" do
    table = create(:iceberg_table, catalog:)

    get iceberg_table_path(table)

    expect(response.body).to include("not enough data to score")
  end
end

RSpec.describe "POST /iceberg_tables/:id/run_maintenance", type: :request do
  let(:user)     { create(:user, :operator) }
  let(:catalog)  { create(:catalog) }
  let(:table)    { create(:iceberg_table, catalog:) }

  before { sign_in user }

  it "creates a default plan and runs it when the table has none" do
    expect(table.maintenance_plan).to be_nil

    post run_maintenance_iceberg_table_path(table)

    expect(response).to redirect_to(iceberg_tables_path)
    expect(table.reload.maintenance_plan).to be_present
    expect(table.maintenance_plan.maintenance_steps.map(&:operation))
      .to contain_exactly(*MaintenancePlan::CANONICAL_ORDER)
    expect(table.maintenance_plan.enabled_steps.map(&:operation))
      .to contain_exactly("optimize", "expire_snapshots")
    expect(table.execution_histories.last.status).to eq("pending")
  end

  it "resumes and runs a paused plan" do
    plan = create(:maintenance_plan, :with_all_steps, iceberg_table: table,
                  is_paused: true, consecutive_failures: 3, needs_review: true)

    post run_maintenance_iceberg_table_path(table)

    expect(response).to redirect_to(iceberg_tables_path)
    plan.reload
    expect(plan.is_paused).to be(false)
    expect(plan.consecutive_failures).to eq(0)
    expect(plan.needs_review).to be(false)
    expect(table.execution_histories.last.status).to eq("pending")
  end

  it "runs an active plan without creating another" do
    plan = create(:maintenance_plan, :with_all_steps, iceberg_table: table)

    post run_maintenance_iceberg_table_path(table)

    expect(response).to redirect_to(iceberg_tables_path)
    expect(table.reload.maintenance_plan).to eq(plan)
    expect(table.execution_histories.last.status).to eq("pending")
  end

  it "does not enqueue a duplicate when a run is already pending" do
    plan = create(:maintenance_plan, :with_all_steps, iceberg_table: table)
    create(:execution_history, iceberg_table: table, maintenance_plan: plan, status: :pending)

    post run_maintenance_iceberg_table_path(table)

    expect(response).to redirect_to(iceberg_tables_path)
    expect(table.execution_histories.where(status: "pending").count).to eq(1)
    expect(flash[:notice]).to include("already queued")
  end

  it "rejects viewers" do
    sign_in create(:user)

    post run_maintenance_iceberg_table_path(table)

    expect(response).to redirect_to(root_path)
    expect(table.reload.maintenance_plan).to be_nil
    expect(table.execution_histories).to be_empty
  end
end

RSpec.describe "POST /iceberg_tables/sync_all", type: :request do
  let(:user)    { create(:user, :admin) }
  let!(:catalog) { create(:catalog) }

  before { sign_in user }

  it "enqueues a sync for every catalog" do
    allow(MaintenanceOrchestrator).to receive(:sync_catalog)

    post sync_all_iceberg_tables_path

    expect(response).to redirect_to(iceberg_tables_path)
    expect(MaintenanceOrchestrator).to have_received(:sync_catalog).with(catalog.id)
  end

  it "rejects viewers" do
    sign_in create(:user)

    post sync_all_iceberg_tables_path

    expect(response).to redirect_to(root_path)
  end
end

RSpec.describe "Pagination", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "paginates without breaking with many tables" do
    create_list(:iceberg_table, 30)

    get iceberg_tables_path

    expect(response).to have_http_status(:ok)
  end

  it "paginates with a filter applied" do
    create_list(:iceberg_table, 30)

    get iceberg_tables_path, params: { q: "a" }

    expect(response).to have_http_status(:ok)
  end
end
