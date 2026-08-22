require "rails_helper"
require "aws-sdk-sts"

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

  describe "S3 storage properties" do
    it "uses the CEPH_ENDPOINT env var for the default s3.endpoint" do
      catalog
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.last.properties
      expect(props["s3.endpoint"]).to eq(ENV.fetch("CEPH_ENDPOINT", "http://ceph.local"))
    end

    it "merges static S3 credentials when configured" do
      create(:catalog, :s3_static, name: "s3-static")
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.last.properties
      expect(props["s3.access-key"]).to eq("AKIAIOSFODNN7EXAMPLE")
      expect(props["s3.secret-key"]).to eq("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    end

    it "does not include s3.access-key when authentication is none" do
      catalog
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.last.properties
      expect(props).not_to have_key("s3.access-key")
    end

    it "includes s3.region when set" do
      create(:catalog, :s3_static, name: "s3-region", s3_region: "eu-west-1")
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.last.properties
      expect(props["s3.region"]).to eq("eu-west-1")
    end

    it "uses per-catalog s3.endpoint over the env default" do
      create(:catalog, :s3_static, name: "s3-custom",
             s3_endpoint: "https://s3.us-west-2.amazonaws.com")
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.last.properties
      expect(props["s3.endpoint"]).to eq("https://s3.us-west-2.amazonaws.com")
    end

    it "calls STS AssumeRole when authentication type is sts" do
      sts_client = instance_double(Aws::STS::Client)
      allow(Aws::STS::Client).to receive(:new).and_return(sts_client)
      allow(sts_client).to receive(:assume_role).and_return(
        double(credentials: double(
          access_key_id: "ASIAIOSFODNN7TEMP",
          secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYTEMPKEY",
          session_token: "FwoGZXIvYXdzEBY"
        ))
      )

      create(:catalog, :s3_sts, name: "s3-sts")
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.last.properties
      expect(props["s3.access-key"]).to eq("ASIAIOSFODNN7TEMP")
      expect(props["s3.secret-key"]).to eq("wJalrXUtnFEMI/K7MDENG/bPxRfiCYTEMPKEY")
      expect(props["s3.session-token"]).to eq("FwoGZXIvYXdzEBY")
    end
  end
end
