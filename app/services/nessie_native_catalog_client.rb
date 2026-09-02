# Catalog client for Nessie over its NATIVE /api/v2 trees API — the access
# model Iceberg's own NessieCatalog uses (client-side warehouse +
# authentication.type). Selected when a Nessie catalog has
# nessie_api_mode == "native".
#
# The response shapes differ from Iceberg REST:
#   * GET /api/v2/trees/{ref}/entries returns a flat "entries" array (with
#     "type", "name.elements", "contentId") and a "token" for pagination,
#     not nested "namespaces"/"identifiers" with "next-page-token".
#   * GET /api/v2/trees/{ref}/contents/{path} returns the Iceberg table
#     Content (metadataLocation), not the full TableMetadata — so the summary
#     metrics stay nil until a maintenance run enriches them via Trino.
class NessieNativeCatalogClient < CatalogClient
  # @return [String] the mount prefix before /v1 (native API has no /v1)
  def mount_prefix
    "/api/v2"
  end

  # The native API has no /v1/config warehouse discovery — the ref and
  # warehouse are client-side settings on the catalog.
  #
  # @return [nil]
  def config_warehouse = nil

  # The native API base is {endpoint}/api/v2 — no /v1/{rest_prefix} segment.
  #
  # @return [String] the base URL for native API calls
  def base_url
    "#{catalog.endpoint}#{mount_prefix}"
  end

  # Walks the tree entries, one flat request per level. Every entry carries a
  # dotted name path; NAMESPACE entries below the current depth become the
  # next level, so the recursion matches Iceberg REST semantics.
  #
  # @return [Array<String>] all descendant namespace paths
  def namespaces
    # The root ("") is listed first so the sync visits tables that live at the
    # repository root, which Nessie permits. Without it those tables were
    # unreachable: the sync only ever calls tables_in for a discovered
    # namespace, so a repository keeping tables at the root imported part of
    # its catalog with no error to say anything was missed.
    [ "" ] + collect_namespaces(nil, 0)
  end

  # Lists the Iceberg table names directly under a namespace.
  #
  # A blank namespace lists the tables at the repository ROOT, which Nessie
  # permits. Those entries have a single-element name and no namespace, so the
  # filter is `entry.namespace == ''` and the prefix guard cannot apply.
  #
  # ICEBERG_VIEW entries are deliberately excluded: the maintenance operations
  # do not apply to views.
  #
  # @param namespace [String] the dotted namespace path ("" for the root)
  # @return [Array<String>] table names in the namespace
  def tables_in(namespace)
    root = namespace.blank?

    entries(root ? "" : namespace).filter_map do |entry|
      next unless entry["type"] == "ICEBERG_TABLE"

      elements = Array(entry.dig("name", "elements"))
      next if elements.empty?

      if root
        # A root table is exactly one element deep; anything deeper belongs to
        # a namespace and is listed by that namespace's own call.
        next unless elements.size == 1
      else
        next unless dotted_name(entry).start_with?("#{namespace}.")
      end

      elements.last
    end.compact
  end

  # Fetches the Iceberg table Content for a table. The native API returns the
  # Content object (metadataLocation), not the full TableMetadata payload the
  # Iceberg REST surface serves — the health summary metrics are therefore nil
  # until maintenance enriches them.
  #
  # @param namespace [String] the dotted namespace path
  # @param table [String] the table name
  # @return [Hash] a { "metadata" => ... }-shaped payload the sync can read
  def table_metadata(namespace, table)
    # A root table's content key is the bare table name - prefixing a blank
    # namespace would send a leading dot and miss the content.
    path = namespace.presence ? "#{namespace}.#{table}" : table
    content = get("#{base_url}/trees/#{ERB::Util.url_encode(ref)}/contents/#{path}")

    {
      "metadata" => {
        "table-uuid" => content["contentId"],
        "location" => content.dig("metadata", "metadataLocation") || content["metadataLocation"],
        "snapshots" => [],
        "current-snapshot-id" => nil
      }
    }
  end

  private

  # The ref the catalog reads (branch/tag). The native API requires an explicit
  # ref in the URL; it defaults to the catalog's configured ref or "main".
  #
  # @return [String] the ref
  def ref
    @ref ||= catalog.nessie_ref.presence || "main"
  end

  # GETs all entries, following the "token" pagination field.
  #
  # Scoping uses the CEL `filter` expression, NOT `key`: in the Nessie v2 API
  # `key` is an exact content-key lookup, so it matched the namespace entry
  # itself and returned nothing beneath it - every namespace listed zero
  # tables. `exact` selects between a namespace's direct contents and its
  # descendants, which is what recursive namespace discovery needs.
  #
  # @param namespace [String, nil] the dotted namespace (nil = whole tree)
  # @param exact [Boolean] true for direct contents, false for descendants
  # @return [Array<Hash>] the raw entry objects
  def entries(namespace, exact: true)
    path = +"/trees/#{ERB::Util.url_encode(ref)}/entries"
    path << "?filter=#{ERB::Util.url_encode(namespace_filter(namespace, exact:))}" if namespace
    path << (path.include?("?") ? "&" : "?") + "max-records=100"

    pages = []
    token = nil
    loop do
      url = +path
      url << "&token=#{ERB::Util.url_encode(token)}" if token

      body = get("#{base_url}#{url}")
      pages.concat(body["entries"] || [])
      token = body["token"]
      break if token.nil? || token.empty?
    end
    pages
  end

  # The CEL expression scoping entries to a namespace.
  #
  # @param namespace [String] the dotted namespace path
  # @param exact [Boolean] true for direct contents, false for descendants
  # @return [String] the CEL filter expression
  def namespace_filter(namespace, exact:)
    literal = escape_cel(namespace)
    exact ? "entry.namespace == '#{literal}'" : "entry.namespace.startsWith('#{literal}')"
  end

  # Escapes a namespace for interpolation into a CEL single-quoted string
  # literal. A name carrying a quote or a backslash would otherwise produce a
  # malformed expression - unlikely, but the value comes from the catalog and
  # is not ours to trust.
  #
  # @param value [String] the raw namespace
  # @return [String] the escaped literal body
  def escape_cel(value)
    value.to_s.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'")
  end

  # The dotted path of an entry from its name.elements array.
  #
  # @param entry [Hash] the entry object
  # @return [String] the dotted name
  def dotted_name(entry)
    Array(entry.dig("name", "elements")).join(".")
  end

  # Collects namespaces recursively, one level at a time via the entries API.
  #
  # @param parent [String, nil] the parent namespace, or nil for the root
  # @param depth [Integer] the current recursion depth
  # @return [Array<String>] all descendant namespace paths
  def collect_namespaces(parent, depth)
    return [] if depth >= MAX_NAMESPACE_DEPTH

    prefix = parent ? "#{parent}." : ""
    # Descendants, not direct contents: a namespace's children are themselves
    # namespaces nested below it.
    children = entries(parent, exact: false).filter_map do |entry|
      next unless entry["type"] == "NAMESPACE"

      name = dotted_name(entry)
      name if name.start_with?(prefix) && name != parent
    end.uniq

    children.flat_map { |child| [ child ] + collect_namespaces(child, depth + 1) }
  rescue HttpTransport::ApiError => e
    # A failure at the root is a configuration problem: propagate it, otherwise
    # the sync "succeeds" having imported zero tables.
    raise if parent.nil?

    Rails.logger.warn("Failed to list namespaces under #{parent.inspect}: #{e.message}")
    []
  end
end
