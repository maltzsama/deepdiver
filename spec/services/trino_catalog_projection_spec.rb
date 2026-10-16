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

  it "omits iceberg.rest-catalog.warehouse for Nessie catalogs" do
    catalog
    described_class.new.sync_all!

    expect(TrinoCatalogRegistry.last.properties).not_to have_key("iceberg.rest-catalog.warehouse")
  end

  it "includes iceberg.rest-catalog.warehouse for Polaris catalogs" do
    polaris = create(:polaris_catalog, name: "Polaris Prod")
    described_class.new.sync_all!

    row = TrinoCatalogRegistry.find_by(catalog_name: "polaris_prod")
    expect(row.properties["iceberg.rest-catalog.warehouse"]).to eq("Polaris Prod")
  end

  describe "iceberg.rest-catalog.uri" do
    it "appends /api/catalog for Polaris catalogs" do
      polaris = create(:polaris_catalog, name: "Polaris Prod")
      described_class.new.sync_all!

      row = TrinoCatalogRegistry.find_by(catalog_name: "polaris_prod")
      expect(row.properties["iceberg.rest-catalog.uri"]).to eq("http://polaris:8181/api/catalog")
    end

    it "does not double-append the Polaris prefix when endpoint already carries it" do
      polaris = create(:polaris_catalog, name: "Polaris Prod",
                       endpoint: "http://polaris:8181/api/catalog")
      described_class.new.sync_all!

      row = TrinoCatalogRegistry.find_by(catalog_name: "polaris_prod")
      expect(row.properties["iceberg.rest-catalog.uri"]).to eq("http://polaris:8181/api/catalog")
    end

    it "appends /iceberg for Nessie catalogs" do
      nessie = create(:catalog, name: "Nessie Prod")
      described_class.new.sync_all!

      row = TrinoCatalogRegistry.find_by(catalog_name: "nessie_prod")
      expect(row.properties["iceberg.rest-catalog.uri"]).to eq("#{nessie.endpoint.chomp('/')}/iceberg")
    end
  end

  it "writes properties as a flat string map" do
    create(:catalog_credential, catalog:, auth_method: "oauth2_client_credentials",
                                client_id: "svc", secret: "s3cr3t", scope: "PRINCIPAL_ROLE:ALL")
    described_class.new.sync_all!

    props = TrinoCatalogRegistry.last.properties
    expect(props.values).to all(be_a(String))
    expect(props["iceberg.rest-catalog.oauth2.credential"]).to match(/\A@baleia-secret\[file:catalog-\d+-iceberg_rest-catalog_oauth2_credential\]\z/)
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

  it "validates reserved catalog names" do
    cluster = TrinoCluster.create!(name: "default")

    record = TrinoCatalogRegistry.new(cluster_id: cluster.id, catalog_name: "system",
                                       connector_name: "iceberg", properties: {})

    expect(record).not_to be_valid
    expect(record.errors[:catalog_name]).to be_present
  end

  it "merges operator catalog properties over the computed defaults" do
    create(:catalog, name: "props-cat",
           properties: { "iceberg.expire-snapshots.min-retention" => "2d",
                         "custom.prop" => "true" })
    described_class.new.sync_all!

    props = TrinoCatalogRegistry.find_by(catalog_name: "props_cat").properties
    expect(props["iceberg.expire-snapshots.min-retention"]).to eq("2d")
    expect(props["custom.prop"]).to eq("true")
    # The fixed defaults still apply where the operator did not override.
    expect(props["iceberg.catalog.type"]).to eq("rest")
  end

  describe "native Nessie mode" do
    it "projects through the REST connector, which reaches nested namespaces (see #238)" do
      create(:catalog, catalog_type: "nessie", name: "native-nessie",
             nessie_api_mode: "native", nessie_ref: "etl_dev",
             nessie_warehouse: "s3://bucket/", endpoint: "http://nessie:19120")
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.find_by(catalog_name: "native_nessie").properties
      expect(props["iceberg.catalog.type"]).to eq("rest")
      expect(props["iceberg.rest-catalog.uri"]).to eq("http://nessie:19120/iceberg")
      expect(props["iceberg.rest-catalog.nested-namespace-enabled"]).to eq("true")
      # The stored warehouse is sent verbatim (Nessie resolves name or
      # location); the ref is NOT sent - the config endpoint rejects it as an
      # unknown warehouse, and the returned prefix embeds the default branch.
      expect(props["iceberg.rest-catalog.warehouse"]).to eq("s3://bucket/")
      expect(props.keys.grep(/nessie-catalog/)).to be_empty
    end

    it "omits the warehouse parameter when none is stored, so the server default answers" do
      create(:catalog, catalog_type: "nessie", name: "native-nessie2",
             nessie_api_mode: "native", nessie_warehouse: "s3://bucket/",
             endpoint: "http://nessie:19120").update_column(:nessie_warehouse, "")
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.find_by(catalog_name: "native_nessie2").properties
      expect(props).not_to have_key("iceberg.rest-catalog.warehouse")
    end

    it "keeps using the REST surface when nessie_api_mode is rest" do
      create(:catalog, catalog_type: "nessie", name: "rest-nessie",
             nessie_api_mode: "rest", endpoint: "http://nessie:19120")
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.find_by(catalog_name: "rest_nessie").properties
      expect(props["iceberg.catalog.type"]).to eq("rest")
      expect(props["iceberg.rest-catalog.uri"]).to eq("http://nessie:19120/iceberg")
    end
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
      expect(props["s3.aws-access-key"]).to match(/\A@baleia-secret\[file:catalog-\d+-s3_aws-access-key\]\z/)
      expect(props["s3.aws-secret-key"]).to match(/\A@baleia-secret\[file:catalog-\d+-s3_aws-secret-key\]\z/)
    end

    it "does not include s3.aws-access-key when authentication is none" do
      catalog
      described_class.new.sync_all!

      props = TrinoCatalogRegistry.last.properties
      expect(props).not_to have_key("s3.aws-access-key")
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
      expect(props["s3.aws-access-key"]).to match(/\A@baleia-secret\[file:catalog-\d+-s3_aws-access-key\]\z/)
      expect(props["s3.aws-secret-key"]).to match(/\A@baleia-secret\[file:catalog-\d+-s3_aws-secret-key\]\z/)
      expect(props["s3.aws-session-token"]).to match(/\A@baleia-secret\[file:catalog-\d+-s3_aws-session-token\]\z/)
    end
  end
end
