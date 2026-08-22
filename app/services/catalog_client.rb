require "erb"

# Base Iceberg REST Catalog client. Talks to Polaris/Nessie over Net::HTTP and
# exposes a narrow interface the sync job needs. Transport is injected, so
# tests never hit the network.
class CatalogClient
  NAMESPACE_SEPARATOR = "\x1F"
  MAX_NAMESPACE_DEPTH = 10

  attr_reader :catalog

  # Creates a client bound to a catalog with an injectable transport.
  #
  # @param catalog [Catalog] the catalog the client talks to
  # @param transport [HttpTransport] the HTTP transport to use (injected for tests)
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

  # Lists the table names directly under a namespace.
  #
  # @param namespace [String] the dotted namespace path
  # @return [Array<String>] table names in the namespace
  def tables_in(namespace)
    body = get("#{base_url}/namespaces/#{encode_namespace(namespace)}/tables")
    (body["identifiers"] || body["tables"] || []).map { |entry| table_name(entry) }
  end

  # Fetches the Iceberg REST TableMetadata for a table.
  #
  # @param namespace [String] the dotted namespace path
  # @param table [String] the table name
  # @return [Hash] the parsed JSON response body
  def table_metadata(namespace, table)
    get("#{base_url}/namespaces/#{encode_namespace(namespace)}/tables/#{ERB::Util.url_encode(table)}")
  end

  private

  # Recursively collects every namespace under a parent, stopping at the max depth.
  #
  # @param parent [String, nil] the parent namespace, or nil for the root
  # @param depth [Integer] the current recursion depth
  # @return [Array<String>] all descendant namespace paths
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

  # Builds the REST base URL from the catalog endpoint and configured path prefix.
  #
  # @return [String] the base URL for catalog REST calls
  def base_url
    suffix = catalog.properties&.dig("path_prefix") || default_path_prefix
    "#{catalog.endpoint}#{suffix}"
  end

  # Path prefix for the catalog REST API; subclasses override this.
  #
  # @return [String] the default path prefix
  def default_path_prefix
    raise NotImplementedError, "#{self.class} must define the default path prefix"
  end

  # Memoized token provider for this catalog.
  #
  # @return [CatalogTokenProvider]
  def token_provider
    @token_provider ||= CatalogTokenProvider.new(catalog, transport: @transport)
  end

  # Performs an authenticated GET against the catalog REST API. A single 401
  # refreshes the derived token and retries once - covers a short-lived token
  # that expired mid-sync without masking real authorization failures (those
  # fail twice and surface as-is).
  #
  # @param path [String] the request path
  # @return [Hash] the parsed JSON response
  def get(path)
    @transport.get(path, headers: token_provider.headers)
  rescue HttpTransport::ApiError => e
    raise if e.status != 401 || @refreshed_token

    @refreshed_token = true
    token_provider.refresh!
    retry
  ensure
    @refreshed_token = false
  end

  # Converts a namespace entry from the REST response into a dotted string.
  #
  # @param entry [Object] a namespace entry (string, name, or namespace key)
  # @return [String] the dotted namespace path
  def namespace_to_dotted_string(entry)
    parts = entry.is_a?(Hash) ? (entry["namespace"] || entry["name"]) : entry
    Array(parts).join(".")
  end

  # Extracts the bare table name from a REST response entry.
  #
  # @param entry [Object] a table entry (string or name key)
  # @return [String] the table name
  def table_name(entry)
    name = entry.is_a?(Hash) ? entry["name"] : entry
    name.to_s.split(".").last || name.to_s
  end
end
