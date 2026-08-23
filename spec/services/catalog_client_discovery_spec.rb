require "rails_helper"

RSpec.describe CatalogClient, "#/v1/config prefix discovery" do
  let(:transport) { instance_double(HttpTransport) }

  def nessie_catalog(props = {})
    create(:catalog, catalog_type: "nessie",
                     endpoint: "http://nessie:19120", properties: props)
  end

  it "mounts /iceberg and uses the discovered default prefix (Nessie)" do
    client = NessieCatalogClient.new(nessie_catalog, transport:)
    allow(transport).to receive(:get)
      .with("http://nessie:19120/iceberg/v1/config", headers: anything)
      .and_return("defaults" => { "prefix" => "main" }, "overrides" => {})

    expect(transport).to receive(:get)
      .with("http://nessie:19120/iceberg/v1/main/namespaces", headers: {})
      .and_return({ "namespaces" => [] })

    client.namespaces
  end

  it "prefers overrides.prefix over defaults.prefix" do
    client = NessieCatalogClient.new(nessie_catalog, transport:)
    allow(transport).to receive(:get)
      .with("http://nessie:19120/iceberg/v1/config", headers: anything)
      .and_return("defaults" => { "prefix" => "main" }, "overrides" => { "prefix" => "etl_dev" })
    allow(transport).to receive(:get)
      .with("http://nessie:19120/iceberg/v1/etl_dev/namespaces", headers: {})
      .and_return({ "namespaces" => [] })

    client.namespaces
  end

  it "pins an explicit nessie_ref over whatever the server discovered" do
    catalog = create(:catalog, catalog_type: "nessie", endpoint: "http://nessie:19120",
                               properties: {}, nessie_ref: "etl_dev")
    client = NessieCatalogClient.new(catalog, transport:)

    expect(transport).not_to receive(:get)
      .with("http://nessie:19120/iceberg/v1/config", headers: anything)
    expect(transport).to receive(:get)
      .with("http://nessie:19120/iceberg/v1/etl_dev/namespaces", headers: {})
      .and_return({ "namespaces" => [] })

    client.namespaces
  end

  it "sends no warehouse param for Nessie and one for Polaris" do
    nessie = NessieCatalogClient.new(nessie_catalog, transport:)
    expect(nessie.config_url).to eq("http://nessie:19120/iceberg/v1/config")

    polaris = create(:polaris_catalog, name: "lakehouse")
    pc = PolarisCatalogClient.new(polaris, transport:)
    expect(pc.config_url).to eq("http://polaris:8181/api/catalog/v1/config?warehouse=lakehouse")
  end

  it "ignores any hand-set path_prefix - discovery is the only regime" do
    catalog = create(:polaris_catalog, name: "lakehouse",
                                       properties: { "path_prefix" => "/v1/lakehouse" })
    client = PolarisCatalogClient.new(catalog, transport:)
    allow(transport).to receive(:get)
      .with("http://polaris:8181/api/catalog/v1/config?warehouse=lakehouse", headers: anything)
      .and_return("defaults" => {}, "overrides" => { "prefix" => "lakehouse" })

    expect(transport).to receive(:get)
      .with("http://polaris:8181/api/catalog/v1/lakehouse/namespaces", headers: {})
      .and_return({ "namespaces" => [] })

    client.namespaces
  end

  it "fails loudly when the server answers config without a prefix" do
    client = NessieCatalogClient.new(nessie_catalog, transport:)
    allow(transport).to receive(:get)
      .with("http://nessie:19120/iceberg/v1/config", headers: anything)
      .and_return("defaults" => {}, "overrides" => {})

    expect { client.namespaces }.to raise_error(HttpTransport::ApiError) # prefixless config aborts before any listing
  end
end
