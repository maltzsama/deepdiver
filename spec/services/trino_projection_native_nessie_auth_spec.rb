require "rails_helper"

RSpec.describe TrinoCatalogProjection, "native Nessie authentication" do
  let(:projection) { described_class.new(cluster_name: "default") }

  def native_catalog(**attrs)
    create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_warehouse: "s3://bucket/", endpoint: "http://nessie:19120", **attrs)
  end

  def props_for(catalog)
    projection.send(:connector_properties, catalog)
  end

  context "without authentication" do
    it "omits authentication.type entirely" do
      # BEARER is the only member of the connector's Security enum, so any
      # sentinel value ("NONE") fails catalog initialization outright.
      props = props_for(native_catalog)

      expect(props).not_to have_key("iceberg.nessie-catalog.authentication.type")
      expect(props).not_to have_key("iceberg.nessie-catalog.authentication.token")
    end

    it "never emits the string NONE for the security property" do
      expect(props_for(native_catalog).values).not_to include("NONE")
    end
  end

  context "with a bearer token" do
    let(:catalog) do
      native_catalog.tap do |c|
        c.create_catalog_credential!(auth_method: "bearer_static", secret: "tok-abc-123")
        c.reload
      end
    end

    it "sets the type to BEARER" do
      expect(props_for(catalog)["iceberg.nessie-catalog.authentication.type"]).to eq("BEARER")
    end

    it "masks the token as a baleia secret ref rather than plaintext" do
      value = props_for(catalog)["iceberg.nessie-catalog.authentication.token"]

      expect(value).to start_with("@baleia-secret[file:")
      expect(props_for(catalog).values.join).not_to include("tok-abc-123")
    end

    it "carries the token through sensitive_property_values so the Secret is written" do
      values = described_class.sensitive_property_values(catalog)

      expect(values["iceberg.nessie-catalog.authentication.token"]).to eq("tok-abc-123")
    end

    it "omits both when the credential is bearer_static but the secret is blank" do
      blank = native_catalog
      blank.create_catalog_credential!(auth_method: "none")
      props = props_for(blank.reload)

      expect(props).not_to have_key("iceberg.nessie-catalog.authentication.type")
      expect(props).not_to have_key("iceberg.nessie-catalog.authentication.token")
    end
  end

  it "does not offer a Nessie token for a REST catalog" do
    rest = create(:catalog, catalog_type: "polaris", endpoint: "http://polaris:8181")
    rest.create_catalog_credential!(auth_method: "bearer_static", secret: "tok-rest")

    expect(described_class.sensitive_property_values(rest.reload))
      .not_to have_key("iceberg.nessie-catalog.authentication.token")
  end

  it "pins the client API version to match the /api/v2 path it builds" do
    props = props_for(native_catalog)

    expect(props["iceberg.nessie-catalog.uri"]).to end_with("/api/v2")
    expect(props["iceberg.nessie-catalog.client-api-version"]).to eq("V2")
  end
end

RSpec.describe TrinoCatalogProjection, "S3 filesystem property" do
  let(:projection) { described_class.new(cluster_name: "default") }

  it "uses the current fs.s3.enabled name for a REST catalog" do
    catalog = create(:catalog, catalog_type: "polaris", endpoint: "http://polaris:8181")
    props = projection.send(:connector_properties, catalog)

    expect(props["fs.s3.enabled"]).to eq("true")
    expect(props).not_to have_key("fs.native-s3.enabled")
  end

  it "uses the current name for a native Nessie catalog too" do
    catalog = create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                               nessie_warehouse: "s3://bucket/", endpoint: "http://nessie:19120")
    props = projection.send(:connector_properties, catalog)

    expect(props["fs.s3.enabled"]).to eq("true")
    expect(props).not_to have_key("fs.native-s3.enabled")
  end
end
