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
    path = "/namespaces/#{encode_namespace(namespace)}/tables"
    paginated_get(path).flat_map do |body|
      (body["identifiers"] || body["tables"] || []).map { |entry| table_name(entry) }
    end
  end

  # Fetches the Iceberg REST TableMetadata for a table.
  #
  # @param namespace [String] the dotted namespace path
  # @param table [String] the table name
  # @return [Hash] the parsed JSON response body
  def table_metadata(namespace, table)
    get("#{base_url}/namespaces/#{encode_namespace(namespace)}/tables/#{ERB::Util.url_encode(table)}")
  end

  # Absolute URL of the /v1/config discovery call, warehouse included when the
  # provider names its warehouses.
  #
  # @return [String]
  def config_url
    url = +"#{catalog.endpoint}#{mount_prefix}/v1/config"
    url << "?warehouse=#{CGI.escape(config_warehouse)}" if config_warehouse.present?
    url.to_s
  end

  # Path segment mounted BEFORE /v1 on the server. Subclasses declare it;
  #
  # @return [String] the mount prefix

  private

  # GETs a path following Iceberg REST pagination: sends pageToken when present
  # and follows next-page-token in the response until the last page. Without
  # this, a truncated listing would silently deactivate every table beyond the
  # first page (deactivate_unseen treats a complete namespace as fully synced).
  #
  # @param path [String] the path under base_url (query string optional)
  # @return [Array<Hash>] every response body across all pages
  def paginated_get(path)
    pages = []
    token = nil

    loop do
      url = +path
      separator = url.include?("?") ? "&" : "?"
      url << "#{separator}pageToken=#{ERB::Util.url_encode(token)}" if token

      body = get("#{base_url}#{url}")
      pages << body
      token = body["next-page-token"]
      break if token.nil? || token.empty?
    end

    pages
  end

  # Recursively collects every namespace under a parent, stopping at the max depth.
  #
  # @param parent [String, nil] the parent namespace, or nil for the root
  # @param depth [Integer] the current recursion depth
  # @return [Array<String>] all descendant namespace paths
  def collect_namespaces(parent, depth)
    return [] if depth >= MAX_NAMESPACE_DEPTH

    path = +"/namespaces"
    path << "?parent=#{encode_namespace(parent)}" if parent.present?

    children = paginated_get(path).flat_map do |body|
      (body["namespaces"] || []).map { |entry| namespace_to_dotted_string(entry) }
    end

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

  # Builds the REST base URL for every catalog call, per the Iceberg REST
  # spec: GET /v1/config discovers the prefix the server wants (Polaris: the
  # warehouse name; Nessie: the ref), and calls go to
  # {mount}/v1/{prefix}/namespaces...
  #
  # @return [String] the base URL for catalog REST calls
  def base_url
    "#{catalog.endpoint}#{mount_prefix}/v1/#{ERB::Util.url_encode(rest_prefix)}"
  end

  # Path segment mounted BEFORE /v1 on the server. Subclasses declare it.
  #
  # @return [String] the mount prefix
  def mount_prefix
    raise NotImplementedError, "#{self.class} must define its mount prefix"
  end

  # The Iceberg REST prefix this client addresses: from GET /v1/config
  # ("overrides.prefix" then "defaults.prefix"), overridden by an explicit
  # Nessie ref. Memoized per client instance - one config call per sync,
  # not per table.
  #
  # @return [String]
  def rest_prefix
    return catalog.nessie_ref if catalog.nessie_ref.present?

    discovered = rest_config.dig("overrides", "prefix") ||
                 rest_config.dig("defaults", "prefix")
    raise HttpTransport::ApiError.new(500, "catalog /v1/config returned no prefix") if discovered.blank?

    discovered.to_s
  end

  # GET {mount}/v1/config per the Iceberg REST spec - the server's own answer
  # about which prefix and defaults to use. Memoized per client instance.
  #
  # @return [Hash] parsed config payload with "defaults" and "overrides"
  def rest_config
    @transport.get(config_url, headers: token_provider.headers)
  end

  # Warehouse sent to /v1/config. Polaris names its warehouses (the catalog
  # name); Nessie defines warehouses server-side and REJECTS unknown names,
  # so it sends none and rides the default.
  #
  # @return [String, nil]
  def config_warehouse = nil

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
