require "rails_helper"

RSpec.describe "GET /", type: :request do
  let(:user)    { create(:user) }
  let(:catalog) { create(:catalog) }

  before { sign_in user }

  it "counts tables by health status" do
    create_list(:iceberg_table, 2, catalog:, health_status: "critical", health_score: 10)
    create(:iceberg_table, catalog:, health_status: "healthy", health_score: 90)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(assigns(:health_counts)).to include("critical" => 2, "healthy" => 1)
    expect(assigns(:total_tables)).to eq(3)
  end

  it "does not break when there are no tables" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(assigns(:total_tables)).to eq(0)
  end

  it "reports when the last sync happened" do
    create(:iceberg_table, catalog:, metadata_synced_at: 5.seconds.ago)

    get root_path

    expect(assigns(:last_sync_at)).to be_present
    expect(response.body).to match(/Synced less than a minute ago/)
  end

  it "includes tables needing action in the triage list" do
    create(:iceberg_table, catalog:, health_status: "critical",
                           health_score: 20, health_status_changed_at: 2.days.ago)

    get root_path

    expect(assigns(:triage).map(&:table).map(&:health_status)).to eq([ "critical" ])
  end

  it "shows an empty state when nothing needs action" do
    get root_path

    expect(response.body).to include("Nothing needs attention")
  end
end

RSpec.describe "Dashboard needs-action feed", type: :request do
  let(:user)    { create(:user) }
  let(:catalog) { create(:catalog) }

  before { sign_in user }

  it "lists open freshness breaches linking to the History freshness tab" do
    table = create(:iceberg_table)
    error = ErrorEvent.record(catalog: table.catalog, schema: table.namespace, table: table.name,
                              operation: ErrorEvent::FRESHNESS_OPERATION, source_system: "freshness",
                              message: "Freshness SLA breached")

    get root_path

    expect(response.body).to include(execution_histories_path(tab: "freshness"))
    expect(response.body).to include("Freshness SLA breached")
  end

  it "lists paused plans linking to the plan" do
    plan = create(:maintenance_plan, is_paused: true)

    get root_path

    expect(response.body).to include(maintenance_plan_path(plan))
  end

  it "keeps the empty state only when freshness triage and paused plans are all empty" do
    table = create(:iceberg_table)
    ErrorEvent.record(catalog: table.catalog, schema: table.namespace, table: table.name,
                      operation: ErrorEvent::FRESHNESS_OPERATION, source_system: "freshness",
                      message: "Freshness SLA breached")

    get root_path

    expect(response.body).not_to include("Nothing needs attention")
    expect(response.body).to include("Freshness SLA breached")
  end
end

RSpec.describe "Dashboard renders the demo chain", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "shows errors section and out-of-SLA tables together" do
    table = create(:iceberg_table)
    create(:table_freshness_sla, iceberg_table: table, status: "late",
                                 breached_since: 2.hours.ago, sla_minutes: 5,
                                 timestamp_column: "ts", timestamp_type: "timestamp_tz")
    error = ErrorEvent.record(catalog: table.catalog, schema: table.namespace, table: table.name,
                              operation: ErrorEvent::FRESHNESS_OPERATION, source_system: "freshness",
                              message: "Freshness SLA breached")

    get root_path

    expect(response.body).to include("Freshness SLA breached")
    expect(response.body).to include(execution_histories_path(tab: "freshness"))
    expect(response.body).to include(iceberg_table_path(table))
    expect(response.body).not_to include("Nothing needs attention")
  end
end
