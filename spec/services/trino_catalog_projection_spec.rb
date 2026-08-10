require "rails_helper"

RSpec.describe TrinoCatalogProjection do
  let(:catalog) { create(:catalog, name: "Polaris Prod", endpoint: "https://polaris.local/api/catalog") }

  it "creates the cluster row when it does not exist" do
    expect { described_class.new(cluster_name: "default").sync_all! }
      .to change(TrinoCluster, :count).by(1)
  end

  it "writes the derived name and the iceberg connector" do
    catalog
    described_class.new.sync_all!

    row = TrinoCatalogRegistry.last
    expect(row.catalog_name).to eq("polaris_prod")
    expect(row.connector_name).to eq("iceberg")
    expect(row.updated_by).to eq("baleia")
  end

  it "does not include connector.name inside properties" do
    catalog
    described_class.new.sync_all!

    expect(TrinoCatalogRegistry.last.properties).not_to have_key("connector.name")
  end

  it "writes properties as a flat string map" do
    create(:catalog_credential, catalog:, auth_method: "oauth2_client_credentials",
                                client_id: "svc", secret: "s3cr3t", scope: "PRINCIPAL_ROLE:ALL")
    described_class.new.sync_all!

    props = TrinoCatalogRegistry.last.properties
    expect(props.values).to all(be_a(String))
    expect(props["iceberg.rest-catalog.oauth2.credential"]).to eq("svc:s3cr3t")
    expect(props["iceberg.rest-catalog.nested-namespace-enabled"]).to eq("true")
  end

  it "is idempotent" do
    catalog
    2.times { described_class.new.sync_all! }

    expect(TrinoCatalogRegistry.count).to eq(1)
  end

  it "soft-deletes a removed catalog instead of deleting the row" do
    catalog
    described_class.new.sync_all!
    catalog.destroy!
    described_class.new.sync_all!

    row = TrinoCatalogRegistry.last
    expect(row.enabled).to be(false)
    expect(TrinoCatalogRegistry.count).to eq(1)
  end

  it "lets the database CHECK block a reserved name" do
    cluster = TrinoCluster.create!(name: "default")

    expect {
      TrinoCatalogRegistry.create!(cluster_id: cluster.id, catalog_name: "system",
                                   connector_name: "iceberg", properties: {})
    }.to raise_error(ActiveRecord::StatementInvalid, /name_format/)
  end
end
