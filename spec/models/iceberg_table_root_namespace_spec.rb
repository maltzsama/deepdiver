require "rails_helper"

RSpec.describe IcebergTable, "root namespace" do
  it "accepts a table at the repository root" do
    table = build(:iceberg_table, namespace: "", name: "rootbl")

    expect(table).to be_valid
  end

  it "still rejects a nil namespace, which is missing data rather than the root" do
    table = build(:iceberg_table, namespace: nil, name: "tbl")

    expect(table).not_to be_valid
    expect(table.errors[:namespace]).to be_present
  end

  it "still requires a name" do
    expect(build(:iceberg_table, namespace: "ns", name: "")).not_to be_valid
  end

  it "keeps uniqueness scoped per catalog at the root" do
    catalog = create(:catalog)
    create(:iceberg_table, catalog:, namespace: "", name: "rootbl")
    duplicate = build(:iceberg_table, catalog:, namespace: "", name: "rootbl")

    expect(duplicate).not_to be_valid
  end
end

RSpec.describe IcebergTable, "Trino identifiers" do
  let(:catalog) { create(:catalog, name: "cat") }

  it "keeps a nested namespace as ONE quoted part, per Trino's three-level model" do
    table = create(:iceberg_table, catalog:, namespace: "parent.child", name: "tbl")

    expect(table.trino_identifier).to eq('"cat"."parent.child"."tbl"')
    expect(table.trino_identifier.scan(/"(?:[^"]|"")*"/).size).to eq(3)
  end

  it "keeps the same shape for metadata tables" do
    table = create(:iceberg_table, catalog:, namespace: "a.b.c", name: "tbl")

    expect(table.trino_metadata_table("files")).to eq('"cat"."a.b.c"."tbl$files"')
  end

  it "refuses to build an identifier for a root table rather than emitting an empty schema" do
    table = create(:iceberg_table, catalog:, namespace: "", name: "rootbl")

    expect { table.trino_identifier }.to raise_error(IcebergTable::RootTableNotAddressable, /root/)
    expect { table.trino_metadata_table("files") }.to raise_error(IcebergTable::RootTableNotAddressable)
  end
end
