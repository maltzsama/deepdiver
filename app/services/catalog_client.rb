# Base Iceberg REST Catalog client. Talks to Polaris/Nessie over Net::HTTP and
# exposes a narrow interface the sync job needs. Transport is injected, so
# tests never hit the network.
class CatalogClient
  attr_reader :catalog

  def initialize(catalog, transport: HttpTransport.new)
    @catalog = catalog
    @transport = transport
  end

  def namespaces
    body = get("#{base_url}/namespaces")
    (body["namespaces"] || []).map { |entry| namespace_to_dotted_string(entry) }
  end

  def tables_in(namespace)
    body = get("#{base_url}/namespaces/#{CGI.escape(namespace)}/tables")
    (body["identifiers"] || body["tables"] || []).map { |entry| table_name(entry) }
  end

  def table_metadata(namespace, table)
    get("#{base_url}/namespaces/#{CGI.escape(namespace)}/tables/#{CGI.escape(table)}")
  end

  private

  def base_url
    suffix = catalog.properties&.dig("path_prefix") || default_path_prefix
    "#{catalog.endpoint}#{suffix}"
  end

  def default_path_prefix
    raise NotImplementedError, "#{self.class} must define the default path prefix"
  end

  def auth_headers
    token = catalog.properties&.dig("bearerToken") || catalog.properties&.dig("token")
    return {} unless token

    { "Authorization" => "Bearer #{token}" }
  end

  def get(path)
    @transport.get(path, headers: auth_headers)
  end

  def namespace_to_dotted_string(entry)
    parts = entry.is_a?(Hash) ? (entry["namespace"] || entry["name"]) : entry
    Array(parts).join(".")
  end

  def table_name(entry)
    name = entry.is_a?(Hash) ? entry["name"] : entry
    name.to_s.split(".").last || name.to_s
  end
end
