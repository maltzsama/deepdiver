require "erb"

# Base Iceberg REST Catalog client. Talks to Polaris/Nessie over Net::HTTP and
# exposes a narrow interface the sync job needs. Transport is injected, so
# tests never hit the network.
class CatalogClient
  NAMESPACE_SEPARATOR = "\x1F"
  MAX_NAMESPACE_DEPTH = 10

  attr_reader :catalog

  def initialize(catalog, transport: HttpTransport.new)
    @catalog = catalog
    @transport = transport
  end

  # Walks the namespace tree recursively. The REST API only returns the direct
  # children of a namespace, so without this recursion anything nested stays
  # invisible to the sync.
  def namespaces
    collect_namespaces(nil, 0)
  end

  def tables_in(namespace)
    body = get("#{base_url}/namespaces/#{encode_namespace(namespace)}/tables")
    (body["identifiers"] || body["tables"] || []).map { |entry| table_name(entry) }
  end

  def table_metadata(namespace, table)
    get("#{base_url}/namespaces/#{encode_namespace(namespace)}/tables/#{ERB::Util.url_encode(table)}")
  end

  private

  def collect_namespaces(parent, depth)
    return [] if depth >= MAX_NAMESPACE_DEPTH

    url = "#{base_url}/namespaces"
    url += "?parent=#{encode_namespace(parent)}" if parent.present?

    children = (get(url)["namespaces"] || []).map { |entry| namespace_to_dotted_string(entry) }

    children.flat_map { |child| [ child ] + collect_namespaces(child, depth + 1) }
  rescue HttpTransport::ApiError => e
    # A failure at the root is a configuration problem: propagate it, otherwise
    # the sync "succeeds" having imported zero tables.
    raise if parent.nil?

    Rails.logger.warn("Failed to list namespaces under #{parent.inspect}: #{e.message}")
    []
  end

  # A nested namespace goes in a single path segment, with the levels joined
  # by the unit separator (0x1F), per the Iceberg REST spec.
  def encode_namespace(namespace)
    ERB::Util.url_encode(namespace.to_s.split(".").join(NAMESPACE_SEPARATOR))
  end

  def base_url
    suffix = catalog.properties&.dig("path_prefix") || default_path_prefix
    "#{catalog.endpoint}#{suffix}"
  end

  def default_path_prefix
    raise NotImplementedError, "#{self.class} must define the default path prefix"
  end

  def auth_headers
    @token_provider ||= CatalogTokenProvider.new(catalog, transport: @transport)
    @token_provider.headers
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
