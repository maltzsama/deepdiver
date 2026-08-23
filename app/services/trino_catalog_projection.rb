# Mirrors catalogs -> trino_catalog_registry, in the format the plugin reads.
#
# Reference: baleia-trino-catalog-store v0.2.1
#   Database.java (SELECT_ALL), CatalogRow.java (validation),
#   docker/initdb/01-schema.sql (CHECKs).
class TrinoCatalogProjection
  WRITER = "baleia"

  SENSITIVE_KEYS = %w[
    iceberg.rest-catalog.oauth2.credential
    s3.access-key
    s3.secret-key
    s3.session-token
  ].freeze

  # Creates the projection for a cluster name.
  #
  # @param cluster_name [String] the Trino cluster name
  def initialize(cluster_name: ENV.fetch("TRINO_CLUSTER_NAME", "default"))
    @cluster_name = cluster_name
  end

  # Upserts every catalog into the registry and soft-deletes removed ones.
  def sync_all!
    cluster_id = ensure_cluster!

    active = Catalog.includes(:catalog_credential).map do |catalog|
      upsert(cluster_id, catalog)
      catalog.trino_catalog_name
    end

    # A catalog removed from the application becomes a soft delete, like the
    # plugin's DROP CATALOG. Deleting the row would leave Trino without a trace
    # of the catalog.
    TrinoCatalogRegistry
      .where(cluster_id: cluster_id, enabled: true)
      .where.not(catalog_name: active)
      .update_all(enabled: false, updated_by: WRITER, updated_at: Time.current)
  end

  private

  # The plugin JOINs by trino_clusters.name. Without the matching row for
  # baleia.cluster-name, boot loads ZERO catalogs without any error.
  def ensure_cluster!
    TrinoCluster.find_or_create_by!(name: @cluster_name).id
  end

  # Upserts one catalog row into the registry.
  #
  # @param cluster_id [Integer] the cluster id
  # @param catalog [Catalog] the catalog to mirror
  def upsert(cluster_id, catalog)
    TrinoCatalogRegistry.upsert(
      {
        cluster_id: cluster_id,
        catalog_name: catalog.trino_catalog_name,
        connector_name: "iceberg",
        properties: connector_properties(catalog),
        enabled: true,
        sync_status: "pending",
        sync_error: nil,
        updated_by: WRITER,
        updated_at: Time.current
      },
      unique_by: %i[cluster_id catalog_name]
    )
  end

  # Plain string->string map - the plugin's parseFlatJson rejects any non-string
  # value and skips the whole row with sync_status='error'.
  #
  # 'connector.name' must NOT be here: CatalogRow.java rejects it explicitly and
  # requires the connector_name column instead.
  def connector_properties(catalog)
    credential = catalog.catalog_credential

    props = {
      "iceberg.catalog.type" => "rest",
      "iceberg.rest-catalog.uri" => rest_catalog_uri(catalog),
      # Nested namespace: the application configures it instead of relying on
      # someone having enabled it on the cluster. See CR-02.
      "iceberg.rest-catalog.nested-namespace-enabled" => "true",
      "fs.native-s3.enabled" => "true",
      "s3.endpoint" => catalog.s3_endpoint.presence || ENV.fetch("CEPH_ENDPOINT", "http://ceph.local"),
      "s3.path-style-access" => "true"
    }

    # Polaris requires the warehouse (its catalog name) in the REST path.
    # Nessie defines warehouses server-side and rejects unknown names, so
    # never send one — the configured default answers.
    props["iceberg.rest-catalog.warehouse"] = catalog.name if catalog.catalog_type == "polaris"

    props["s3.region"] = catalog.s3_region if catalog.s3_region.present?

    if credential&.oauth2?
      props["iceberg.rest-catalog.security"] = "OAUTH2"
      props["iceberg.rest-catalog.oauth2.credential"] =
        "#{credential.client_id}:#{credential.secret}"
      props["iceberg.rest-catalog.oauth2.scope"] = credential.scope
    end

    props.merge!(catalog.resolve_s3_credentials)

    props.each do |key, value|
      next unless SENSITIVE_KEYS.include?(key) && value.present?

      props[key] = "@baleia-secret[file:catalog-#{catalog.id}-#{key.gsub('.', '_')}]"
    end

    props.transform_values(&:to_s)
  end

  # Base URI Trino's REST client talks to. Nessie mounts the Iceberg surface
  # at /iceberg (empirical, 0.108.4); Polaris at /api/catalog. The prefix
  # itself is discovered by each client's own /v1/config call.
  #
  # @param catalog [Catalog] the catalog being projected
  # @return [String] the REST base URI without trailing slash
  def rest_catalog_uri(catalog)
    uri = catalog.endpoint.chomp("/")
    uri = "#{uri}/iceberg" if catalog.catalog_type == "nessie"
    uri
  end
end
