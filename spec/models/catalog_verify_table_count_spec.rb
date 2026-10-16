require "rails_helper"

RSpec.describe Catalog, "#verify_connection! table count" do
  let(:catalog) { create(:catalog) }

  def stub_client(namespaces:, tables: {})
    client = instance_double(CatalogClient, namespaces: namespaces)
    allow(client).to receive(:tables_in) { |ns| tables.fetch(ns, []) }
    allow(CatalogClientFactory).to receive(:for).with(catalog).and_return(client)
    client
  end

  it "reports the table count alongside the namespace count" do
    stub_client(namespaces: %w[a b], tables: { "a" => %w[t1 t2], "b" => %w[t3] })

    result = catalog.verify_connection!

    expect(result[:ok]).to be(true)
    expect(result[:namespace_count]).to eq(2)
    expect(result[:table_count]).to eq(3)
  end

  it "reports zero tables, which is what makes a broken listing visible" do
    stub_client(namespaces: %w[a b], tables: {})

    result = catalog.verify_connection!

    expect(result[:namespace_count]).to eq(2)
    expect(result[:table_count]).to eq(0)
  end

  it "does not fail verification when one namespace listing raises" do
    client = stub_client(namespaces: %w[good bad], tables: { "good" => %w[t1] })
    allow(client).to receive(:tables_in).with("bad").and_raise(StandardError, "boom")

    result = catalog.verify_connection!

    expect(result[:ok]).to be(true)
    expect(result[:table_count]).to eq(1)
  end

  it "caps how many namespaces it walks, since verification is interactive" do
    many = (1..40).map { |i| "ns#{i}" }
    client = stub_client(namespaces: many, tables: many.to_h { |ns| [ ns, [ "t" ] ] })

    result = catalog.verify_connection!

    expect(result[:table_count]).to eq(described_class::VERIFY_NAMESPACE_SAMPLE)
    expect(client).to have_received(:tables_in).exactly(described_class::VERIFY_NAMESPACE_SAMPLE).times
  end

  it "still reports a failure when namespace discovery itself raises" do
    allow(CatalogClientFactory).to receive(:for).with(catalog)
      .and_return(instance_double(CatalogClient).tap { |c| allow(c).to receive(:namespaces).and_raise(StandardError, "down") })

    expect(catalog.verify_connection!).to include(ok: false, error: "down")
  end
end

RSpec.describe Catalog, "#verify_connection! Trino projection pre-flight" do
  let(:catalog) do
    create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_warehouse: "cephlab", endpoint: "http://nessie:19120")
  end

  before do
    client = instance_double(CatalogClient, namespaces: %w[a])
    allow(client).to receive(:tables_in).and_return(%w[t])
    allow(CatalogClientFactory).to receive(:for).with(catalog).and_return(client)
  end

  it "probes the exact config call Trino will make, warehouse included" do
    transport = instance_double(HttpTransport)
    allow(HttpTransport).to receive(:new).and_return(transport)
    expect(transport).to receive(:get)
      .with("http://nessie:19120/iceberg/v1/config?warehouse=cephlab").and_return({})

    expect(catalog.verify_connection![:ok]).to be(true)
  end

  it "fails verification with the server's reason when the warehouse does not resolve" do
    transport = instance_double(HttpTransport)
    allow(HttpTransport).to receive(:new).and_return(transport)
    allow(transport).to receive(:get)
      .and_raise(HttpTransport::ApiError.new(500, '{"error":{"message":"Warehouse \'x\' is not known"}}'))

    result = catalog.verify_connection!

    expect(result[:ok]).to be(false)
    expect(result[:error]).to include("is not known")
    expect(result[:error]).to include("nessie.catalog.warehouses")
  end

  it "does not probe for rest-mode or non-Nessie catalogs" do
    rest = create(:catalog, catalog_type: "polaris", endpoint: "http://polaris:8181")
    client = instance_double(CatalogClient, namespaces: [])
    allow(client).to receive(:tables_in).and_return([])
    allow(CatalogClientFactory).to receive(:for).with(rest).and_return(client)
    expect(HttpTransport).not_to receive(:new)

    expect(rest.verify_connection![:ok]).to be(true)
  end
end
