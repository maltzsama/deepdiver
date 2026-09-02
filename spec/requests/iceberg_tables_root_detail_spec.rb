require "rails_helper"

RSpec.describe "root-level table detail", type: :request do
  let(:user) { create(:user, role: :admin) }
  let(:catalog) { create(:catalog, name: "cat") }

  before { sign_in user }

  it "renders the detail page instead of 500ing" do
    table = create(:iceberg_table, catalog:, namespace: "", name: "air_searches_raw")

    get iceberg_table_path(table)

    expect(response).to have_http_status(:ok)
  end

  it "explains that the table has no addressable identifier" do
    table = create(:iceberg_table, catalog:, namespace: "", name: "currency")

    get iceberg_table_path(table)

    expect(response.body).to include(I18n.t("tables.show.not_addressable_root"))
  end

  it "still shows the identifier for an addressable table" do
    table = create(:iceberg_table, catalog:, namespace: "silver", name: "orders")

    get iceberg_table_path(table)

    expect(response.body).to include("&quot;cat&quot;.&quot;silver&quot;.&quot;orders&quot;")
    expect(response.body).not_to include(I18n.t("tables.show.not_addressable_root"))
  end

  it "refuses a run instead of raising while building a default plan" do
    table = create(:iceberg_table, catalog:, namespace: "", name: "currency")

    post run_maintenance_iceberg_table_path(table)

    expect(response).to have_http_status(:redirect)
    expect(flash[:alert]).to eq(I18n.t("tables.run_maintenance.not_addressable_root"))
    expect(table.reload.maintenance_plan).to be_nil
  end
end

RSpec.describe IcebergTable, "addressability" do
  let(:catalog) { create(:catalog, name: "cat") }

  it "reports a root table as not addressable" do
    expect(build(:iceberg_table, catalog:, namespace: "", name: "t")).not_to be_addressable_in_trino
  end

  it "reports a namespaced table as addressable" do
    expect(build(:iceberg_table, catalog:, namespace: "ns", name: "t")).to be_addressable_in_trino
  end

  describe "#trino_identifier_for_display" do
    it "is nil for a root table rather than raising" do
      table = create(:iceberg_table, catalog:, namespace: "", name: "t")

      expect { table.trino_identifier_for_display }.not_to raise_error
      expect(table.trino_identifier_for_display).to be_nil
    end

    it "returns the identifier when there is one" do
      table = create(:iceberg_table, catalog:, namespace: "ns", name: "t")

      expect(table.trino_identifier_for_display).to eq('"cat"."ns"."t"')
    end
  end

  it "keeps raising on the execution path, where a statement must not be built" do
    table = create(:iceberg_table, catalog:, namespace: "", name: "t")

    expect { table.trino_identifier }.to raise_error(IcebergTable::RootTableNotAddressable)
    expect { table.trino_metadata_table("files") }.to raise_error(IcebergTable::RootTableNotAddressable)
  end
end

RSpec.describe MaintenancePlan, "root-table guard" do
  let(:catalog) { create(:catalog, name: "cat") }

  it "refuses a plan for a table that cannot be addressed" do
    table = create(:iceberg_table, catalog:, namespace: "", name: "t")
    plan = build(:maintenance_plan, iceberg_table: table, cron: "0 2 * * *")

    expect(plan).not_to be_valid
    expect(plan.errors[:iceberg_table].join).to match(/root/)
  end

  it "allows a plan for a namespaced table" do
    table = create(:iceberg_table, catalog:, namespace: "ns", name: "t")

    expect(build(:maintenance_plan, iceberg_table: table, cron: "0 2 * * *")).to be_valid
  end
end
