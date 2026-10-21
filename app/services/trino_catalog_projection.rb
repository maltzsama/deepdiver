# Mirrors catalogs -> trino_catalog_registry, in the format the plugin reads.
#
# Reference: baleia-trino-catalog-store v0.2.1
#   Database.java (SELECT_ALL), CatalogRow.java (validation),
#   docker/initdb/01-schema.sql (CHECKs).
class TrinoCatalogProjection
  WRITER = "baleia"

  SENSITIVE_KEYS = %w[
    iceberg.rest-catalog.oauth2.credential
    iceberg.rest-catalog.oauth2.token
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
    # A static bearer token (native-Nessie included) rides the REST
    # connector's OAUTH2 mode as a fixed token. It goes through the same
    # masking path as every other secret, so the plaintext never reaches the
    # registry's JSON column - and bearer_credential? gates the security mode
    # on exactly this condition, so mode and token cannot diverge.
    values["iceberg.rest-catalog.oauth2.token"] = credential.secret if bearer_credential?(catalog)
    values.merge!(catalog.resolve_s3_credentials)
    values.select { |key, value| SENSITIVE_KEYS.include?(key) && value.present? }
          .transform_values(&:to_s)
  end

  # Whether this Nessie catalog uses the native /api/v2 access model.
  #
  # A class method because sensitive_property_values (also class-level) needs
  # it to decide whether a bearer token applies.
  #
  # @param catalog [Catalog] the catalog being projected
  # @return [Boolean]
  def self.native_nessie?(catalog)
    catalog.catalog_type == "nessie" && catalog.nessie_api_mode == "native"
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

    # EVERY catalog projects to Trino through the REST connector, including
    # native-mode Nessie. The native Nessie connector (iceberg.catalog.type=
    # nessie) never splits the schema string into namespace levels
    # (TrinoNessieCatalog#namespaceExists, IcebergNessieUtil#toIdentifier), so
    # tables in nested namespaces are unreachable through it under ANY SQL
    # syntax - see #238. The REST connector splits under
    # nested-namespace-enabled, and hooking Trino to Nessie via REST is also
    # what Nessie's own Trino guide prescribes. nessie_api_mode stays what it
    # always was: how the APP discovers the catalog, not how Trino reaches it.
    props = rest_catalog_properties(catalog)

    # The retention floors come from the engine config as typed, validated
    # fields (see #216). They used to be reachable only by hand-editing the
    # catalog's properties JSON with the raw connector key.
    props.merge!(TrinoEngineConfig.instance.connector_retention_properties)

    # The operator's catalog-level Iceberg connector properties (the stored
    # properties JSON, already validated to carry no secrets) are merged over
    # the computed defaults. This remains the escape hatch for connector
    # settings the projection does not model - it is merged LAST, so a
    # per-catalog override still wins over the engine-wide floor. Catalog
    # values never win over the sensitive refs below.
    props.merge!(catalog.properties.stringify_keys.transform_values(&:to_s))

    props["s3.region"] = catalog.s3_region if catalog.s3_region.present?

    # Sensitive values never enter the registry (plain-text JSON column):
    # each becomes an @baleia-secret[file:…] ref.  Ref name and Secret key
    # both derive from secret_file_name over the SAME sensitive_property_values
    # — they cannot drift.
    self.class.sensitive_property_values(catalog).each_key do |key|
      props[key] = "@baleia-secret[file:#{self.class.secret_file_name(catalog, key)}]"
    end

    props.transform_values(&:to_s)
  end

  # Instance-side shorthand for the class-level predicate.
  #
  # @param catalog [Catalog] the catalog being projected
  # @return [Boolean]
  def native_nessie?(catalog) = self.class.native_nessie?(catalog)

  # Connector properties for the Iceberg REST surface (Polaris, Nessie-rest,
  # and any future REST-backed catalog).
  #
  # @param catalog [Catalog] the catalog being projected
  # @return [Hash{String => String}] the REST properties
  def rest_catalog_properties(catalog)
    credential = catalog.catalog_credential

    props = {
      "iceberg.catalog.type" => "rest",
      "iceberg.rest-catalog.uri" => rest_catalog_uri(catalog),
      # Nested namespace: the application configures it instead of relying on
      # someone having enabled it on the cluster. See CR-02.
      "iceberg.rest-catalog.nested-namespace-enabled" => "true",
      # fs.native-s3.enabled is a legacy alias the filesystem manager still
      # accepts but reports as replaced. fs.s3.enabled is the current name.
      "fs.s3.enabled" => "true",
      "s3.endpoint" => catalog.s3_endpoint.presence || ENV.fetch("CEPH_ENDPOINT", "http://ceph.local"),
      "s3.path-style-access" => "true"
    }

    # Polaris requires the warehouse (its catalog name) in the REST path.
    # Nessie defines warehouses server-side and rejects unknown names, so
    # never send one — the configured default answers.
    props["iceberg.rest-catalog.warehouse"] = catalog.name if catalog.catalog_type == "polaris"

    # Live-verified against Nessie: the REST config endpoint resolves the
    # `warehouse` parameter by NAME or by LOCATION (both answered 200 with a
    # usable prefix), and does NOT decode it as a {ref}|{warehouse} prefix -
    # "main" and "main|<wh>" are both rejected as unknown warehouses. So the
    # catalog's stored warehouse is sent verbatim, and the ref is NOT sent:
    # the returned prefix embeds the server's default branch. A server with a
    # default warehouse answers with the field blank. Catalogs pinned to a
    # non-default ref cannot express it through the REST connector - that is
    # a connector-surface limit, documented, not silently worked around.
    if self.class.native_nessie?(catalog) && catalog.nessie_warehouse.present?
      props["iceberg.rest-catalog.warehouse"] = catalog.nessie_warehouse
    end

    if credential&.oauth2?
      props["iceberg.rest-catalog.security"] = "OAUTH2"
      props["iceberg.rest-catalog.oauth2.scope"] = credential.scope
    elsif bearer_credential?(catalog)
      # A static bearer token rides the OAUTH2 security mode with a fixed
      # token - the configuration Nessie's own Trino guide uses. The token
      # itself is masked as a baleia secret ref via SENSITIVE_KEYS below.
      props["iceberg.rest-catalog.security"] = "OAUTH2"
    end

    props
  end

  # Whether the catalog authenticates with a static bearer token.
  #
  # Class-level because sensitive_property_values needs the same predicate:
  # the security mode and the token are gated on one condition, so they
  # cannot diverge.
  #
  # @param catalog [Catalog] the catalog being projected
  # @return [Boolean]
  def self.bearer_credential?(catalog)
    credential = catalog.catalog_credential
    credential&.auth_method == "bearer_static" && credential.secret.present?
  end

  # Instance-side shorthand.
  # @param catalog [Catalog] the catalog being projected
  # @return [Boolean]
  def bearer_credential?(catalog) = self.class.bearer_credential?(catalog)


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
