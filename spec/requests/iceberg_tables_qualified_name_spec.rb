require "rails_helper"

RSpec.describe "tables list qualified names", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "distinguishes same-named tables in different catalogs" do
    prod = create(:catalog, name: "polaris_prod")
    stage = create(:catalog, name: "polaris_stage")
    create(:iceberg_table, catalog: prod, namespace: "silver", name: "orders")
    create(:iceberg_table, catalog: stage, namespace: "silver", name: "orders")

    get iceberg_tables_path

    expect(response.body).to include("polaris_prod.silver.orders")
    expect(response.body).to include("polaris_stage.silver.orders")
  end
end
