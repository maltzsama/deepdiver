require "rails_helper"

RSpec.describe "GET /iceberg_tables", type: :request do
  let(:user)     { create(:user) }
  let(:catalog)  { create(:catalog, name: "polaris_prod") }
  let(:outro)    { create(:catalog, name: "nessie_legado") }

  let!(:critica) do
    create(:iceberg_table, catalog:, namespace: "bronze", name: "vendas",
                           health_status: "critical", health_score: 10)
  end
  let!(:saudavel) do
    create(:iceberg_table, catalog:, namespace: "silver", name: "clientes",
                           health_status: "healthy", health_score: 95)
  end
  let!(:de_outro_catalogo) do
    create(:iceberg_table, catalog: outro, namespace: "bronze", name: "pedidos",
                           health_status: "warning", health_score: 50)
  end

  before { sign_in user }

  it "lists everything, worst score first" do
    get iceberg_tables_path

    expect(response.body.index("vendas")).to be < response.body.index("clientes")
  end

  it "filters by catalog" do
    get iceberg_tables_path, params: { catalog_id: catalog.id }

    expect(response.body).to include("vendas")
    expect(response.body).not_to include("pedidos")
  end

  it "filters by health status" do
    get iceberg_tables_path, params: { health_status: "critical" }

    expect(response.body).to include("vendas")
    expect(response.body).not_to include("clientes")
  end

  it "filters by namespace" do
    get iceberg_tables_path, params: { namespace: "silver" }

    expect(response.body).to include("clientes")
    expect(response.body).not_to include("vendas")
  end

  it "searches by name without case sensitivity" do
    get iceberg_tables_path, params: { q: "VEND" }

    expect(response.body).to include("vendas")
    expect(response.body).not_to include("clientes")
  end

  it "combines filters" do
    get iceberg_tables_path, params: { catalog_id: catalog.id, health_status: "healthy" }

    expect(response.body).to include("clientes")
    expect(response.body).not_to include("vendas")
  end

  it "flags tables without a schedule" do
    get iceberg_tables_path

    expect(response.body).to include("none")
  end
end
