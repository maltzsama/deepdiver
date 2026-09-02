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
