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

  # Syncs every namespace/table of the catalog and refreshes local health
  # signals. Tables that no longer exist in the catalog are soft-deleted so
  # their history is kept.
  #
  # @return [Hash] the list of collected errors under the `errors` key
  def sync
    errors = []
    seen = []

    @client.namespaces.each do |namespace|
      begin
        @client.tables_in(namespace).each do |table_name|
          begin
            seen << upsert_table(namespace, table_name)
          rescue StandardError => e
            ErrorEvent.record(catalog: @catalog, schema: namespace, table: table_name,
                              operation: "sync-table", source_system: "catalog",
                              error_class: e.class.name, message: e.message)
            errors << "#{namespace}.#{table_name}: #{e.message}"
            Rails.logger.warn("Sync failed for #{namespace}.#{table_name}: #{e.message}")
          end
        end
      rescue StandardError => e
        ErrorEvent.record(catalog: @catalog, schema: namespace, operation: "sync-namespace",
                          source_system: "catalog", error_class: e.class.name, message: e.message)
        errors << "namespace #{namespace}: #{e.message}"
        Rails.logger.warn("Sync failed for namespace #{namespace}: #{e.message}")
      end
    end

    deactivate_unseen(seen)
    { errors: errors }
  end

  private

  # Marks as inactive every table of the catalog that was not seen in this
  # sync - they were dropped from the catalog and their history is preserved.
  #
  # @param seen [Array<IcebergTable>] the tables synced in this run.
  def deactivate_unseen(seen)
    seen_ids = seen.map(&:id)
    @catalog.iceberg_tables.active.where.not(id: seen_ids).find_each do |table|
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
    previous_status = table.health_status
    health = HealthEvaluator.evaluate(extractor, plan: table.maintenance_plan, now: @now)

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
      total_size_bytes: extractor.total_size_bytes,
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
    if health[:score]
      attributes[:health_score] = health[:score]
      attributes[:health_status] = health[:status].to_s
    end

    # Só carimba quando MUDA de estado. Sem isso, todo sync reiniciaria o
    # relógio e a ordenação por "quebrou agora" seria sempre a ordem do sync.
    attributes[:health_status_changed_at] = @now if attributes[:health_status] &&
                                                    attributes[:health_status] != previous_status

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
