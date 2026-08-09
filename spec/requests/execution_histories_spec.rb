require "rails_helper"

RSpec.describe "GET /execution_histories", type: :request do
  let(:user)    { create(:user) }
  let(:catalog) { create(:catalog) }
  let(:outro)   { create(:catalog, name: "outro") }

  let(:tabela)       { create(:iceberg_table, catalog:, name: "vendas") }
  let(:tabela_outra) { create(:iceberg_table, catalog: outro, name: "pedidos") }

  let(:optimize) { create(:maintenance_schedule, iceberg_table: tabela, operation: "optimize") }
  let(:expire)   { create(:maintenance_schedule, iceberg_table: tabela, operation: "expire_snapshots") }
  let(:alheia)   { create(:maintenance_schedule, iceberg_table: tabela_outra, operation: "optimize") }

  let!(:falha)   { optimize.execution_histories.create!(status: :failed, current_step: :executing_sql, error_message: "commit conflict") }
  let!(:sucesso) { expire.execution_histories.create!(status: :success, current_step: :done) }
  let!(:de_fora) { alheia.execution_histories.create!(status: :success, current_step: :done) }

  before { sign_in user }

  it "lists executions, most recent first" do
    get execution_histories_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("vendas")
  end

  it "filters by status" do
    get execution_histories_path, params: { status: "failed" }

    expect(response.body).to include("commit conflict")
    expect(response.body).not_to include("pedidos")
  end

  it "filters by operation" do
    get execution_histories_path, params: { operation: "expire_snapshots" }

    expect(response.body).not_to include("commit conflict")
  end

  it "filters by catalog" do
    get execution_histories_path, params: { catalog_id: outro.id }

    expect(response.body).to include("pedidos")
    expect(response.body).not_to include("vendas")
  end

  it "shows the full error message, not truncated" do
    get execution_histories_path

    expect(response.body).to include("commit conflict")
  end
end
