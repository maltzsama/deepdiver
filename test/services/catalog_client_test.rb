require "test_helper"

# Records requests and serves canned JSON, so the client parsing is testable
# without the network.
class StubCatalogTransport
  attr_reader :requests

  def initialize(responses = {})
    @responses = responses
    @requests = []
  end

  def get(path, headers: {})
    @requests << [ :get, path, headers ]
    @responses.fetch(path) { raise "unexpected GET #{path}" }
  end

  def post(*)
    raise "unexpected POST"
  end

  def delete(*)
    raise "unexpected DELETE"
  end
end

class CatalogClientTest < ActiveSupport::TestCase
  def build_catalog
    Catalog.new(name: "analytics", catalog_type: "polaris", endpoint: "http://polaris:8181",
                properties: { "bearerToken" => "secret" })
  end

  test "namespaces are flattened to dotted strings" do
    transport = StubCatalogTransport.new(
      "http://polaris:8181/api/catalog/v1/namespaces" => {
        "namespaces" => [ { "namespace" => %w[reporting dwd] }, { "namespace" => [ "raw" ] } ]
      }
    )
    client = PolarisCatalogClient.new(build_catalog, transport: transport)

    assert_equal [ "reporting.dwd", "raw" ], client.namespaces
    assert_equal({ "Authorization" => "Bearer secret" }, transport.requests.first[2])
  end

  test "table names are read from the identifiers list" do
    transport = StubCatalogTransport.new(
      "http://nessie:19120/api/v1/namespaces/reporting/tables" => {
        "identifiers" => [ { "name" => "dwd_orders" }, { "name" => "dwd_items" } ]
      }
    )
    client = NessieCatalogClient.new(Catalog.new(catalog_type: "nessie", endpoint: "http://nessie:19120"),
                                     transport: transport)

    assert_equal [ "dwd_orders", "dwd_items" ], client.tables_in("reporting")
  end

  test "metadata returns the raw table payload" do
    transport = StubCatalogTransport.new(
      "http://polaris:8181/api/catalog/v1/namespaces/reporting/tables/dwd_orders" => { "metadata" => { "snapshots" => [] } }
    )
    client = PolarisCatalogClient.new(build_catalog, transport: transport)

    assert_equal({ "metadata" => { "snapshots" => [] } }, client.table_metadata("reporting", "dwd_orders"))
  end

  test "factory resolves the client by catalog type" do
    assert_kind_of PolarisCatalogClient, CatalogClientFactory.for(Catalog.new(catalog_type: "polaris"))
    assert_kind_of NessieCatalogClient, CatalogClientFactory.for(Catalog.new(catalog_type: "nessie"))
    assert_raises(ArgumentError) { CatalogClientFactory.for(Catalog.new(catalog_type: "bogus")) }
  end
end
