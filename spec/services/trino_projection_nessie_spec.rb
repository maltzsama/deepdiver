require "rails_helper"

RSpec.describe TrinoCatalogProjection, "nessie uri" do
  let(:projection) { described_class.new(cluster_name: "default") }

  it "mounts the /iceberg surface in the projected URI" do
    catalog = create(:catalog, catalog_type: "nessie",
                               endpoint: "http://nessie:19120",
                               nessie_ref: "etl_dev")

    projection.sync_all!

    row = TrinoCatalogRegistry.find_by!(catalog_name: catalog.trino_catalog_name)
    expect(row.properties["iceberg.rest-catalog.uri"]).to eq("http://nessie:19120/iceberg")
  end

  it "leaves Polaris URIs untouched" do
    catalog = create(:polaris_catalog, name: "polaris-prod", endpoint: "https://polaris.local/api/catalog")

    projection.sync_all!

    row = TrinoCatalogRegistry.find_by!(catalog_name: catalog.trino_catalog_name)
    expect(row.properties["iceberg.rest-catalog.uri"]).to eq("https://polaris.local/api/catalog")
  end
end
