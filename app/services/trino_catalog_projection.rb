# Mirrors catalogs -> trino_catalog_registry, in the format the plugin reads.
#
# Reference: baleia-trino-catalog-store v0.2.1
#   Database.java (SELECT_ALL), CatalogRow.java (validation),
#   docker/initdb/01-schema.sql (CHECKs).
class TrinoCatalogProjection
  WRITER = "baleia"

  SENSITIVE_KEYS = %w[
    iceberg.rest-catalog.oauth2.credential
    s3.aws-access-key
    s3.aws-secret-key
    s3.aws-session-token
  ].freeze

  # Sensitive {trino_property_key => plaintext_value} for a catalog, BEFORE
  # masking.  Single source of truth for what goes into the Secret mounted by
  # baleia: #connector_properties masks each entry as @baleia-secret[file:…]
  # and TrinoSecretMaterializer writes each entry under #secret_file_name —
  # refs and Secret keys can no longer diverge.  STS calls AssumeRole here
  # (session credentials are always fresh).
  def self.sensitive_property_values(catalog)
    values = {}
    credential = catalog.catalog_credential
    if credential&.oauth2?
      values["iceberg.rest-catalog.oauth2.credential"] = "#{credential.client_id}:#{credential.secret}"
    end
    values.merge!(catalog.resolve_s3_credentials)
    values.select { |key, value| SENSITIVE_KEYS.include?(key) && value.present? }
          .transform_values(&:to_s)
  end

  # File name mounted by baleia — MUST match the ref in #connector_properties
  # byte-for-byte.  Derived from the same key the ref uses (dot→underscore,
  # hyphen preserved).
  def self.secret_file_name(catalog, property_key)
    "catalog-#{catalog.id}-#{property_key.gsub('.', '_')}"
  end

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
      props["iceberg.rest-catalog.oauth2.scope"] = credential.scope
    end

    # Sensitive values never enter the registry (plain-text JSON column):
    # each becomes an @baleia-secret[file:…] ref.  Ref name and Secret key
    # both derive from secret_file_name over the SAME sensitive_property_values
    # — they cannot drift.
    self.class.sensitive_property_values(catalog).each_key do |key|
      props[key] = "@baleia-secret[file:#{self.class.secret_file_name(catalog, key)}]"
    end

    props.transform_values(&:to_s)
  end

  # Base URI Trino's Iceberg REST connector talks to. Unlike the app's own
  # Ruby-side REST client (which appends its mount prefix itself via
  # CatalogClient#base_url / mount_prefix), Trino uses iceberg.rest-catalog.uri
  # as the literal REST root — it never discovers a prefix via /v1/config.
  # So the mount path must already be in the URI:
  #   Nessie  → /iceberg     (empirical, 0.108.4)
  #   Polaris → /api/catalog (mirrors PolarisCatalogClient#mount_prefix)
  #
  # @param catalog [Catalog] the catalog being projected
  # @return [String] the REST base URI without trailing slash
  def rest_catalog_uri(catalog)
    uri = catalog.endpoint.chomp("/")
    case catalog.catalog_type
    when "nessie"  then uri.end_with?("/iceberg") ? uri : "#{uri}/iceberg"
    when "polaris" then uri.end_with?("/api/catalog") ? uri : "#{uri}/api/catalog"
    else                uri
    end
  end
end
