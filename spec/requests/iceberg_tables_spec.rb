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

  it "flags tables without a schedule" do
    get iceberg_tables_path

    expect(response.body).to include("none")
  end
end
