require "rails_helper"

RSpec.describe NessieNativeCatalogClient do
  let(:catalog) do
    create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_ref: "main", nessie_warehouse: "s3://bucket/",
                     endpoint: "http://nessie:19120")
  end

  def client_with(transport)
    described_class.new(catalog, transport:).tap do |c|
      allow(c).to receive(:rest_config).and_return("defaults" => { "prefix" => "iceberg" })
    end
  end

  it "lists namespaces and tables from the native entries API" do
    transport = instance_double(HttpTransport)
    allow(transport).to receive(:get)
      .with(%r{/trees/main/entries}, headers: anything)
      .and_return(
        "entries" => [
          { "type" => "NAMESPACE", "name" => { "elements" => [ "bronze" ] }, "contentId" => "n1" },
          { "type" => "NAMESPACE", "name" => { "elements" => [ "silver" ] }, "contentId" => "n2" },
          { "type" => "ICEBERG_TABLE", "name" => { "elements" => [ "bronze", "orders" ] }, "contentId" => "t1" }
        ]
      )
    allow(transport).to receive(:get)
      .with(%r{/trees/main/entries\?.*filter=.*bronze}, headers: anything)
      .and_return(
        "entries" => [ { "type" => "ICEBERG_TABLE", "name" => { "elements" => [ "bronze", "orders" ] }, "contentId" => "t1" } ]
      )

    client = client_with(transport)

    expect(client.namespaces).to include("bronze", "silver")
    expect(client.tables_in("bronze")).to include("orders")
  end

  it "follows the entries pagination token" do
    transport = instance_double(HttpTransport)
    allow(transport).to receive(:get)
      .with(%r{/trees/main/entries\z|/trees/main/entries\?.*max-records}, headers: anything)
      .and_return(
        "entries" => [ { "type" => "NAMESPACE", "name" => { "elements" => [ "a" ] } } ],
        "token" => "tok-1"
      )
    allow(transport).to receive(:get)
      .with(%r{token=tok-1}, headers: anything)
      .and_return("entries" => [ { "type" => "NAMESPACE", "name" => { "elements" => [ "b" ] } } ])
    allow(transport).to receive(:get)
      .with(%r{filter=}, headers: anything)
      .and_return("entries" => [])

    client = client_with(transport)

    expect(client.namespaces).to include("a", "b")
  end

  it "builds a metadata payload from the table content" do
    transport = instance_double(HttpTransport)
    allow(transport).to receive(:get)
      .with(%r{/trees/main/contents/bronze\.orders}, headers: anything)
      .and_return("contentId" => "table-uuid-1",
                  "metadataLocation" => "s3://bucket/metadata/v1.metadata.json")
    client = client_with(transport)

    payload = client.table_metadata("bronze", "orders")

    expect(payload["metadata"]["table-uuid"]).to eq("table-uuid-1")
    expect(payload["metadata"]["location"]).to eq("s3://bucket/metadata/v1.metadata.json")
  end
end

RSpec.describe NessieNativeCatalogClient, "entries scoping" do
  let(:catalog) do
    create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                     nessie_ref: "main", nessie_warehouse: "s3://bucket/",
                     endpoint: "http://nessie:19120")
  end

  # Captures every URL the client requests so the query string can be asserted.
  def recording_transport(entries: [])
    urls = []
    transport = instance_double(HttpTransport)
    allow(transport).to receive(:get) do |url, **|
      urls << url
      { "entries" => entries }
    end
    [ transport, urls ]
  end

  it "scopes a table listing with an exact CEL namespace filter, not key=" do
    transport, urls = recording_transport
    described_class.new(catalog, transport:).tables_in("ns.child")

    expect(urls.first).to include(ERB::Util.url_encode("entry.namespace == 'ns.child'"))
    expect(urls.first).not_to include("key=")
  end

  it "scopes namespace recursion with the startsWith prefix form" do
    transport, urls = recording_transport
    described_class.new(catalog, transport:).send(:collect_namespaces, "ns", 0)

    expect(urls.first).to include(ERB::Util.url_encode("entry.namespace.startsWith('ns')"))
  end

  it "escapes a quote so the CEL expression stays well formed" do
    transport, urls = recording_transport
    described_class.new(catalog, transport:).tables_in("it's")

    expect(urls.first).to include(ERB::Util.url_encode("entry.namespace == 'it\\'s'"))
  end

  describe "tables at the repository root" do
    it "lists them with an empty-namespace filter" do
      root_table = { "type" => "ICEBERG_TABLE", "name" => { "elements" => [ "rootbl" ] }, "contentId" => "t9" }
      transport, urls = recording_transport(entries: [ root_table ])

      tables = described_class.new(catalog, transport:).tables_in("")

      expect(urls.first).to include(ERB::Util.url_encode("entry.namespace == ''"))
      expect(tables).to eq([ "rootbl" ])
    end

    it "does not mistake a namespaced table for a root table" do
      nested = { "type" => "ICEBERG_TABLE", "name" => { "elements" => [ "ns", "tbl" ] } }
      transport, = recording_transport(entries: [ nested ])

      expect(described_class.new(catalog, transport:).tables_in("")).to be_empty
    end

    it "includes the root in the namespace list so the sync visits it" do
      transport, = recording_transport
      expect(described_class.new(catalog, transport:).namespaces).to include("")
    end

    it "asks for a root table's content by its bare name" do
      urls = []
      transport = instance_double(HttpTransport)
      allow(transport).to receive(:get) do |url, **|
        urls << url
        { "contentId" => "c1", "metadataLocation" => "s3://b/m.json" }
      end

      described_class.new(catalog, transport:).table_metadata("", "rootbl")

      expect(urls.first).to end_with("/contents/rootbl")
    end
  end

  it "excludes views, which maintenance does not apply to" do
    view = { "type" => "ICEBERG_VIEW", "name" => { "elements" => [ "ns", "vw" ] } }
    table = { "type" => "ICEBERG_TABLE", "name" => { "elements" => [ "ns", "tbl" ] } }
    transport, = recording_transport(entries: [ view, table ])

    expect(described_class.new(catalog, transport:).tables_in("ns")).to eq([ "tbl" ])
  end
end
