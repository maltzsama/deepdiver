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
  POLARIS_CONFIG = "http://polaris:8181/api/catalog/v1/config?warehouse=analytics"
  NESSIE_CONFIG  = "http://nessie:19120/iceberg/v1/config"

  def build_catalog
    catalog = Catalog.find_or_create_by!(name: "analytics") do |c|
      c.catalog_type = "polaris"
      c.endpoint = "http://polaris:8181"
    end
    catalog.create_catalog_credential!(auth_method: "bearer_static", secret: "secret") unless catalog.catalog_credential
    catalog
  end

  test "namespaces are flattened to dotted strings" do
    transport = StubCatalogTransport.new(
      POLARIS_CONFIG => { "defaults" => { "prefix" => "analytics" } },
      "http://polaris:8181/api/catalog/v1/analytics/namespaces" => {
        "namespaces" => [ { "namespace" => %w[reporting dwd] }, { "namespace" => [ "raw" ] } ]
      },
      "http://polaris:8181/api/catalog/v1/analytics/namespaces?parent=reporting%1Fdwd" => { "namespaces" => [] },
      "http://polaris:8181/api/catalog/v1/analytics/namespaces?parent=raw" => { "namespaces" => [] }
    )
    client = PolarisCatalogClient.new(build_catalog, transport: transport)

    assert_equal [ "reporting.dwd", "raw" ], client.namespaces
    assert_equal({ "Authorization" => "Bearer secret" }, transport.requests.first[2])
  end

  test "namespaces recurses into nested children" do
    transport = StubCatalogTransport.new(
      POLARIS_CONFIG => { "defaults" => { "prefix" => "analytics" } },
      "http://polaris:8181/api/catalog/v1/analytics/namespaces" => {
        "namespaces" => [ { "namespace" => %w[bronze vendas] } ]
      },
      "http://polaris:8181/api/catalog/v1/analytics/namespaces?parent=bronze%1Fvendas" => {
        "namespaces" => [ { "namespace" => %w[bronze vendas raw] }, { "namespace" => %w[bronze vendas silver] } ]
      },
      "http://polaris:8181/api/catalog/v1/analytics/namespaces?parent=bronze%1Fvendas%1Fraw" => { "namespaces" => [] },
      "http://polaris:8181/api/catalog/v1/analytics/namespaces?parent=bronze%1Fvendas%1Fsilver" => { "namespaces" => [] }
    )
    client = PolarisCatalogClient.new(build_catalog, transport: transport)

    assert_equal [ "bronze.vendas", "bronze.vendas.raw", "bronze.vendas.silver" ], client.namespaces
  end

  test "tables_in encodes nested namespace with the unit separator" do
    transport = StubCatalogTransport.new(
      POLARIS_CONFIG => { "defaults" => { "prefix" => "analytics" } },
      "http://polaris:8181/api/catalog/v1/analytics/namespaces/bronze%1Fvendas/tables" => {
        "identifiers" => [ { "name" => "pedidos" } ]
      }
    )
    client = PolarisCatalogClient.new(build_catalog, transport: transport)

    assert_equal [ "pedidos" ], client.tables_in("bronze.vendas")
    table_request = transport.requests.find { |r| r[1].include?("/namespaces/") }
    assert_equal "http://polaris:8181/api/catalog/v1/analytics/namespaces/bronze%1Fvendas/tables",
                 table_request[1]
  end

  test "table names are read from the identifiers list" do
    transport = StubCatalogTransport.new(
      NESSIE_CONFIG => { "defaults" => { "prefix" => "main" } },
      "http://nessie:19120/iceberg/v1/main/namespaces/reporting/tables" => {
        "identifiers" => [ { "name" => "dwd_orders" }, { "name" => "dwd_items" } ]
      }
    )
    client = NessieCatalogClient.new(Catalog.new(catalog_type: "nessie", endpoint: "http://nessie:19120"),
                                     transport: transport)

    assert_equal [ "dwd_orders", "dwd_items" ], client.tables_in("reporting")
  end

  test "metadata returns the raw table payload" do
    transport = StubCatalogTransport.new(
      POLARIS_CONFIG => { "defaults" => { "prefix" => "analytics" } },
      "http://polaris:8181/api/catalog/v1/analytics/namespaces/reporting/tables/dwd_orders" => { "metadata" => { "snapshots" => [] } }
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
