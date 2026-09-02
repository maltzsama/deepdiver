# Materialises the "lightweight" sync path: list namespaces and tables via the
# catalog REST API, read TableMetadata (last snapshot, snapshot count) and
# refresh the local health signals. Never touches Trino.
class CatalogSyncService
  # Creates the sync service for a catalog, defaulting the client and clock.
  #
  # @param catalog [Catalog] the catalog to sync
  # @param client [CatalogClient, nil] an injectable catalog client
  # @param now [Time] the reference clock for health evaluation
  def initialize(catalog, client: nil, now: Time.current)
    @catalog = catalog
    @client = client || CatalogClientFactory.for(catalog)
    @now = now
  end

  # Refreshes a single table's metadata without re-syncing the whole catalog.
  #
  # The Trino catalog Secret is materialized for ALL catalogs: it is a single
  # shared Secret built as a full replacement, so passing only this table's
  # catalog would delete every other catalog's S3/OAuth2 credentials.
  #
  # @param table [IcebergTable] the table to refresh
  # @return [Hash] { ok: true } or { ok: false, error: message }
  def sync_table(table)
    TrinoSecretMaterializer.new.materialize!(Catalog.includes(:catalog_credential))
    upsert_table(table.namespace, table.name)
    { ok: true }
  rescue StandardError => e
    Rails.logger.warn("Per-table sync failed for #{table.fully_qualified_name}: #{e.message}")
    ErrorEvent.record(catalog: table.catalog, schema: table.namespace, table: table.name,
                      operation: "sync-table", source_system: "catalog",
                      error_class: e.class.name, message: e.message)
    { ok: false, error: e.message }
  end

  # Convenience: refresh a single table by its id.
  # @param table_id [Integer]
  # @return [Hash]
  def self.sync_table(table_id)
    table = IcebergTable.includes(:catalog).find(table_id)
    new(table.catalog).sync_table(table)
  end

  # Enriches a table with metrics that require a Trino query (engine must be
  # up). Called on the post-maintenance resync path when the engine is already
  # running. Never forces an engine start.
  #
  # Queries $files for total size and $manifests for manifest count, updating
  # the table's persisted columns so health evaluation can use them.
  #
  # @param table [IcebergTable] the table to enrich
  # @return [void]
  def self.enrich_from_trino!(table)
    catalog_name = table.catalog.trino_catalog_name
    client = TrinoClient.new(catalog_name: catalog_name)

    files_sql = %(SELECT SUM(file_size_in_bytes) AS total FROM #{table.trino_metadata_table("files")})
    total_size = client.query_scalar(files_sql, "total")
    table.update_column(:total_size_bytes, total_size.to_i) if total_size

    manifests_sql = %(SELECT COUNT(*) AS n FROM #{table.trino_metadata_table("manifests")})
    manifest_count = client.query_scalar(manifests_sql, "n")
    table.update_column(:manifest_count, manifest_count.to_i) if manifest_count

    # Re-evaluate health with the newly available Trino data.
    extractor = TableMetadataExtractor.from_persisted(table)
    health = HealthEvaluator.evaluate(extractor, plan: table.maintenance_plan,
                                          manifest_count: manifest_count&.to_i)
    attributes = table.health_attributes(health)
    table.update_columns(attributes) if attributes.any?
  rescue StandardError => e
    Rails.logger.warn("enrich_from_trino! failed for #{table.fully_qualified_name}: #{e.message}")
  end

  # Syncs every namespace/table of the catalog and refreshes local health
  # signals. Tables that no longer exist in the catalog are soft-deleted so
  # their history is kept.
  #
  # @return [Hash] the list of collected errors under the `errors` key
  def sync
    TrinoSecretMaterializer.new.materialize!(Catalog.includes(:catalog_credential))
    errors = []
    seen = []

    # Only namespaces whose listing succeeded AND whose every table synced can
    # authorise a deactivation. A namespace that errored tells us nothing about
    # what it contains, so its tables must be left alone.
    complete_namespaces = []

    @client.namespaces.each do |namespace|
      begin
        namespace_failed = false

        @client.tables_in(namespace).each do |table_name|
          begin
            seen << upsert_table(namespace, table_name)
          rescue StandardError => e
            namespace_failed = true
            ErrorEvent.record(catalog: @catalog, schema: namespace, table: table_name,
                              operation: "sync-table", source_system: "catalog",
                              error_class: e.class.name, message: e.message)
            errors << "#{namespace}.#{table_name}: #{e.message}"
            Rails.logger.warn("Sync failed for #{namespace}.#{table_name}: #{e.message}")
          end
        end

        complete_namespaces << namespace unless namespace_failed
      rescue StandardError => e
        ErrorEvent.record(catalog: @catalog, schema: namespace, operation: "sync-namespace",
                          source_system: "catalog", error_class: e.class.name, message: e.message)
        errors << "namespace #{namespace}: #{e.message}"
        Rails.logger.warn("Sync failed for namespace #{namespace}: #{e.message}")
      end
    end

    deactivate_unseen(seen, complete_namespaces)

    if errors.any? { |e| e.match?(/secret|file|resolve/i) }
      ErrorEvent.record(
        catalog: @catalog, schema: "security", operation: "secret-resolution",
        source_system: "app", severity: "warning",
        error_class: "SecretResolutionFailure",
        message: "Catalog #{@catalog.name}: secret file not yet available — check trino-catalog-secrets and secret-file-base-dir"
      )
    end

    { errors: errors }
  end

  private

  # Marks as inactive the tables that the catalog no longer lists, so their
  # history is preserved.
  #
  # Restricted to namespaces that synced completely. A table missing from `seen`
  # because its own sync raised, or because its namespace failed to list, has
  # not been dropped from the catalog - we simply do not know its state, and
  # deactivating it removes it from the tables screen, from freshness sweeps
  # (which filter on active) and from maintenance dispatch. A transient catalog
  # error used to silence monitoring for every table it touched; with every
  # namespace failing, `where.not(id: [])` renders as `1=1` and took out the
  # whole catalog.
  #
  # @param seen [Array<IcebergTable>] the tables synced in this run.
  # @param complete_namespaces [Array<String>] namespaces that synced with no errors.
  def deactivate_unseen(seen, complete_namespaces)
    return if complete_namespaces.empty?

    scope = @catalog.iceberg_tables.active.where(namespace: complete_namespaces)
    seen_ids = seen.map(&:id).compact
    scope = scope.where.not(id: seen_ids) if seen_ids.any?

    scope.find_each do |table|
      table.deactivate!
      Rails.logger.info("Table #{table.fully_qualified_name} dropped from catalog; marked inactive")
    end
  end

  # Creates or updates a table row from catalog metadata and its health score.
  # Identity is the catalog's table-uuid: an existing row with the same uuid is
  # updated, otherwise a new row is created (drop + recreate = new table).
  #
  # @param namespace [String] the dotted namespace path
  # @param table_name [String] the table name
  # @return [IcebergTable] the persisted table
  def upsert_table(namespace, table_name)
    payload = @client.table_metadata(namespace, table_name)
    extractor = TableMetadataExtractor.new(payload["metadata"] || payload)

    table = find_or_initialize_table(namespace, table_name, extractor.table_uuid)
    # manifest_count comes from the persisted Trino enrichment, not the catalog
    # summary — pass it so the persisted health_score matches the detail page
    # and enrich_from_trino! (see #198).
    health = HealthEvaluator.evaluate(extractor, plan: table.maintenance_plan,
                                      manifest_count: table.manifest_count, now: @now)

    attributes = {
      namespace: namespace,
      name: table_name,
      active: true,
      deactivated_at: nil,
      last_data_update: extractor.last_snapshot_at,
      table_uuid: extractor.table_uuid,
      storage_location: extractor.storage_location,
      total_records: extractor.total_records,
      total_data_files: extractor.total_data_files,
      position_deletes: extractor.position_deletes,
      equality_deletes: extractor.equality_deletes,
      snapshot_count: extractor.snapshot_count,
      oldest_snapshot_at: extractor.oldest_snapshot_at,
      metadata_synced_at: @now,
      schema_json: extractor.schemas,
      partition_json: extractor.partition_specs,
      refs_json: extractor.refs,
      properties_json: extractor.properties,
      snapshots_json: extractor.snapshots
    }
    # A nil size from the catalog must never clear a value the Trino
    # enrichment already measured — the two sources have different
    # availability. Only write size when the catalog actually carried it.
    attributes[:total_size_bytes] = extractor.total_size_bytes if extractor.total_size_bytes

    # One writer shape for the score, the status label and the breakdown, so
    # they can never be persisted from different evaluations (see #215). The
    # status_changed_at stamping lives there too.
    attributes.merge!(table.health_attributes(health, at: @now))

    table.update!(attributes)
    table
  end

  # Locates a table by its catalog uuid, falling back to the name when the
  # metadata carries no uuid (tables listed but metadata not yet readable).
  #
  # @param namespace [String] the dotted namespace path
  # @param table_name [String] the table name
  # @param table_uuid [String, nil] the catalog table-uuid
  # @return [IcebergTable] a persisted or new (unsaved) table
  def find_or_initialize_table(namespace, table_name, table_uuid)
    return @catalog.iceberg_tables.find_or_initialize_by(namespace: namespace, name: table_name) if table_uuid.blank?

    @catalog.iceberg_tables.find_or_initialize_by(table_uuid: table_uuid)
  end
end
