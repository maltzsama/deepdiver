require "rails_helper"

RSpec.describe TrinoCatalogProjection, "native-mode Nessie projected via the REST connector" do
  let(:projection) { described_class.new(cluster_name: "default") }

  def native_catalog(**attrs)
    create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_warehouse: "s3://bucket/", endpoint: "http://nessie:19120", **attrs)
  end

  def props_for(catalog)
    projection.send(:connector_properties, catalog)
  end

  it "uses the REST connector, whose namespace handling splits the dotted schema" do
    props = props_for(native_catalog)

    expect(props["iceberg.catalog.type"]).to eq("rest")
    expect(props["iceberg.rest-catalog.uri"]).to eq("http://nessie:19120/iceberg")
    expect(props["iceberg.rest-catalog.nested-namespace-enabled"]).to eq("true")
  end

  it "emits no native-connector key at all" do
    expect(props_for(native_catalog).keys.grep(/nessie-catalog/)).to be_empty
  end

  it "sends the stored warehouse verbatim - Nessie resolves it by name or by location (live-verified)" do
    expect(props_for(native_catalog)["iceberg.rest-catalog.warehouse"]).to eq("s3://bucket/")
    expect(props_for(native_catalog(nessie_warehouse: "cephlab"))["iceberg.rest-catalog.warehouse"]).to eq("cephlab")
  end

  it "never sends the ref as the warehouse - the config endpoint rejects it as an unknown warehouse" do
    props = props_for(native_catalog(nessie_ref: "etl_dev"))

    expect(props["iceberg.rest-catalog.warehouse"]).not_to eq("etl_dev")
  end

  it "does not change rest-mode Nessie catalogs" do
    rest = create(:catalog, catalog_type: "nessie", nessie_api_mode: "rest",
                            nessie_ref: "etl_dev", endpoint: "http://nessie:19120")

    expect(props_for(rest)).not_to have_key("iceberg.rest-catalog.warehouse")
  end

  context "with a static bearer token" do
    let(:catalog) do
      native_catalog.tap do |c|
        c.create_catalog_credential!(auth_method: "bearer_static", secret: "tok-abc-123")
        c.reload
      end
    end

    it "rides OAUTH2 with a fixed token, per Nessie's own Trino guide" do
      props = props_for(catalog)

      expect(props["iceberg.rest-catalog.security"]).to eq("OAUTH2")
      expect(props["iceberg.rest-catalog.oauth2.token"]).to start_with("@baleia-secret[file:")
    end

    it "never leaks the plaintext into the registry properties" do
      expect(props_for(catalog).values.join).not_to include("tok-abc-123")
    end

    it "carries the token through sensitive_property_values so the Secret is written" do
      expect(described_class.sensitive_property_values(catalog)["iceberg.rest-catalog.oauth2.token"])
        .to eq("tok-abc-123")
    end

    it "emits neither mode nor token when the secret is blank" do
      blank = native_catalog
      blank.create_catalog_credential!(auth_method: "none")
      props = props_for(blank.reload)

      expect(props).not_to have_key("iceberg.rest-catalog.security")
      expect(props).not_to have_key("iceberg.rest-catalog.oauth2.token")
    end
  end
end

RSpec.describe TrinoCatalogProjection, "S3 filesystem property" do
  let(:projection) { described_class.new(cluster_name: "default") }

  it "uses fs.s3.enabled for a REST catalog" do
    catalog = create(:catalog, catalog_type: "polaris", endpoint: "http://polaris:8181")
    props = projection.send(:connector_properties, catalog)

    expect(props["fs.s3.enabled"]).to eq("true")
    expect(props).not_to have_key("fs.native-s3.enabled")
  end

  it "uses fs.s3.enabled for a native-mode Nessie catalog too" do
    catalog = create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                               nessie_warehouse: "s3://bucket/", endpoint: "http://nessie:19120")
    props = projection.send(:connector_properties, catalog)

    expect(props["fs.s3.enabled"]).to eq("true")
  end
end
