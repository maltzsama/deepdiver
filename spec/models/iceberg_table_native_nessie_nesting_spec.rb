require "rails_helper"

RSpec.describe IcebergTable, "addressability on a native-Nessie catalog" do
  def native_nessie
    create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_warehouse: "s3://b/", endpoint: "http://nessie:19120")
  end

  def nessie_rest
    create(:catalog, catalog_type: "nessie", nessie_api_mode: "rest", endpoint: "http://nessie:19120")
  end

  context "native mode, where the connector never splits the schema" do
    it "reports a nested namespace as unaddressable" do
      table = create(:iceberg_table, catalog: native_nessie, namespace: "parent.child", name: "tbl")

      expect(table).not_to be_addressable_in_trino
      expect(table.unaddressable_reason).to eq(:nested_native_nessie)
    end

    it "still allows a single-level namespace" do
      table = create(:iceberg_table, catalog: native_nessie, namespace: "single", name: "tbl")

      expect(table).to be_addressable_in_trino
      expect(table.unaddressable_reason).to be_nil
    end

    it "reports the root reason for a root table, not the nesting one" do
      table = create(:iceberg_table, catalog: native_nessie, namespace: "", name: "tbl")

      expect(table.unaddressable_reason).to eq(:root)
    end

    it "raises with a message naming the connector behaviour" do
      table = create(:iceberg_table, catalog: native_nessie, namespace: "a.b", name: "tbl")

      expect { table.trino_identifier }
        .to raise_error(IcebergTable::NotAddressableInTrino, /does not split the schema/)
      expect { table.trino_metadata_table("files") }
        .to raise_error(IcebergTable::NotAddressableInTrino)
    end

    it "returns nil from the display accessor rather than raising" do
      table = create(:iceberg_table, catalog: native_nessie, namespace: "a.b", name: "tbl")

      expect(table.trino_identifier_for_display).to be_nil
    end
  end

  context "REST mode, where the connector does split" do
    it "allows a nested namespace" do
      table = create(:iceberg_table, catalog: nessie_rest, namespace: "parent.child", name: "tbl")

      expect(table).to be_addressable_in_trino
    end

    it "still emits the dotted three-part identifier" do
      catalog = create(:catalog, catalog_type: "polaris", name: "cat", endpoint: "http://polaris:8181")
      table = create(:iceberg_table, catalog:, namespace: "a.b", name: "tbl")

      expect(table.trino_identifier).to eq('"cat"."a.b"."tbl"')
    end
  end

  it "keeps the old error constant working for existing rescues" do
    expect(IcebergTable::RootTableNotAddressable).to eq(IcebergTable::NotAddressableInTrino)
  end
end

RSpec.describe MaintenancePlan, "native-Nessie nesting guard" do
  let(:catalog) do
    create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_warehouse: "s3://b/", endpoint: "http://nessie:19120")
  end

  it "refuses a plan for a nested table, naming the connector reason" do
    table = create(:iceberg_table, catalog:, namespace: "parent.child", name: "tbl")
    plan = build(:maintenance_plan, iceberg_table: table, cron: "0 2 * * *")

    expect(plan).not_to be_valid
    expect(plan.errors[:iceberg_table].join).to match(/nested namespace/)
  end

  it "allows a plan for a single-level namespace on the same catalog" do
    table = create(:iceberg_table, catalog:, namespace: "single", name: "tbl")

    expect(build(:maintenance_plan, iceberg_table: table, cron: "0 2 * * *")).to be_valid
  end
end

RSpec.describe "nested native-Nessie table detail", type: :request do
  let(:user) { create(:user, role: :admin) }
  let(:catalog) do
    create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_warehouse: "s3://b/", endpoint: "http://nessie:19120")
  end

  before { sign_in user }

  it "renders instead of 500ing, explaining the connector limitation" do
    table = create(:iceberg_table, catalog:, namespace: "parent.child", name: "tbl")

    get iceberg_table_path(table)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("tables.show.not_addressable_nested_native_nessie"))
  end

  it "refuses Run with the reason and creates no plan" do
    table = create(:iceberg_table, catalog:, namespace: "parent.child", name: "tbl")

    post run_maintenance_iceberg_table_path(table)

    expect(flash[:alert]).to eq(I18n.t("tables.run_maintenance.not_addressable_nested_native_nessie"))
    expect(table.reload.maintenance_plan).to be_nil
  end
end
