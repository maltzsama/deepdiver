require "rails_helper"

RSpec.describe IcebergTable, "nested namespaces on a native-Nessie catalog" do
  def native_nessie
    create(:catalog, name: "cat", catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_warehouse: "s3://b/", endpoint: "http://nessie:19120")
  end

  it "is addressable: the projection reaches Trino through the REST connector, which splits the schema" do
    table = create(:iceberg_table, catalog: native_nessie, namespace: "parent.child", name: "tbl")

    expect(table).to be_addressable_in_trino
    expect(table.unaddressable_reason).to be_nil
  end

  it "emits the dotted three-part identifier the REST connector expects" do
    table = create(:iceberg_table, catalog: native_nessie, namespace: "parent.child", name: "tbl")

    expect(table.trino_identifier).to eq('"cat"."parent.child"."tbl"')
    expect(table.trino_metadata_table("files")).to eq('"cat"."parent.child"."tbl$files"')
  end

  it "accepts a maintenance plan for a nested table" do
    table = create(:iceberg_table, catalog: native_nessie, namespace: "parent.child", name: "tbl")

    expect(build(:maintenance_plan, iceberg_table: table, cron: "0 2 * * *")).to be_valid
  end

  it "still refuses a table at the catalog root, the one genuinely unaddressable case" do
    table = create(:iceberg_table, catalog: native_nessie, namespace: "", name: "rootbl")

    expect(table.unaddressable_reason).to eq(:root)
    expect { table.trino_identifier }.to raise_error(IcebergTable::NotAddressableInTrino, /root/)
  end

  it "keeps the old error constant working for existing rescues" do
    expect(IcebergTable::RootTableNotAddressable).to eq(IcebergTable::NotAddressableInTrino)
  end
end

RSpec.describe "nested native-Nessie table detail", type: :request do
  let(:user) { create(:user, role: :admin) }
  let(:catalog) do
    create(:catalog, name: "cat", catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_warehouse: "s3://b/", endpoint: "http://nessie:19120")
  end

  before { sign_in user }

  it "shows the identifier instead of a limitation notice" do
    table = create(:iceberg_table, catalog:, namespace: "parent.child", name: "tbl")

    get iceberg_table_path(table)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("&quot;cat&quot;.&quot;parent.child&quot;.&quot;tbl&quot;")
  end
end
