# Mirrors catalogs -> trino_catalog_registry, in the format the plugin reads.
#
# Reference: baleia-trino-catalog-store v0.2.1
#   Database.java (SELECT_ALL), CatalogRow.java (validation),
#   docker/initdb/01-schema.sql (CHECKs).
class TrinoCatalogProjection
  WRITER = "baleia"

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
      "iceberg.rest-catalog.uri" => catalog.endpoint,
      # Nested namespace: the application configures it instead of relying on
      # someone having enabled it on the cluster. See CR-02.
      "iceberg.rest-catalog.nested-namespace-enabled" => "true",
      "fs.native-s3.enabled" => "true",
      "s3.endpoint" => ENV.fetch("CEPH_ENDPOINT", "http://ceph.local"),
      "s3.path-style-access" => "true"
    }

    if credential&.oauth2?
      props["iceberg.rest-catalog.security"] = "OAUTH2"
      props["iceberg.rest-catalog.oauth2.credential"] =
        "#{credential.client_id}:#{credential.secret}"
      props["iceberg.rest-catalog.oauth2.scope"] = credential.scope
    end

    props.transform_values(&:to_s)
  end
end
