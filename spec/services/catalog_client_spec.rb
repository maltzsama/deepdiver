require "rails_helper"

RSpec.describe CatalogClient do
  it "propagates a root failure instead of returning an empty list" do
    transport = instance_double(HttpTransport)
    allow(transport).to receive(:get).and_raise(HttpTransport::ApiError.new(404, ""))
    client = NessieCatalogClient.new(create(:catalog, catalog_type: "nessie"), transport:)

    expect { client.namespaces }.to raise_error(HttpTransport::ApiError)
  end

  describe "pagination" do
    let(:catalog) { create(:catalog, catalog_type: "nessie") }

    def client_with(transport)
      NessieCatalogClient.new(catalog, transport:).tap do |c|
        allow(c).to receive(:rest_config).and_return("defaults" => { "prefix" => "iceberg" })
      end
    end

    it "follows next-page-token in tables_in until the last page" do
      transport = instance_double(HttpTransport)
      allow(transport).to receive(:get)
        .with(%r{/namespaces/ns/tables\z}, headers: anything)
        .and_return("identifiers" => [ { "name" => "t1" } ], "next-page-token" => "abc")
      allow(transport).to receive(:get)
        .with(%r{/namespaces/ns/tables\?.*pageToken=abc}, headers: anything)
        .and_return("identifiers" => [ { "name" => "t2" } ])
      client = client_with(transport)

      expect(client.tables_in("ns")).to contain_exactly("t1", "t2")
    end

    it "follows next-page-token in collect_namespaces" do
      transport = instance_double(HttpTransport)
      allow(transport).to receive(:get)
        .with(%r{/namespaces\z}, headers: anything)
        .and_return("namespaces" => [ { "namespace" => [ "a" ] } ], "next-page-token" => "xyz")
      allow(transport).to receive(:get)
        .with(%r{/namespaces\?.*pageToken=xyz}, headers: anything)
        .and_return("namespaces" => [ { "namespace" => [ "b" ] } ])
      allow(transport).to receive(:get)
        .with(%r{parent=}, headers: anything)
        .and_return("namespaces" => [])
      client = client_with(transport)

      expect(client.namespaces).to include("a", "b")
    end

    it "sends no pageToken on the first request" do
      transport = instance_double(HttpTransport)
      allow(transport).to receive(:get)
        .with(%r{/namespaces/ns/tables\z}, headers: anything)
        .and_return("identifiers" => [])
      client = client_with(transport)

      expect(client.tables_in("ns")).to be_empty
    end
  end
end
