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
      .with(%r{/trees/main/entries\?.*key=bronze}, headers: anything)
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
      .with(%r{key=}, headers: anything)
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
