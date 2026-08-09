# Materialises the "lightweight" sync path: list namespaces and tables via the
# catalog REST API, read TableMetadata (last snapshot, snapshot count) and
# refresh the local health signals. Never touches Trino.
class CatalogSyncService
  def initialize(catalog, client: nil, now: Time.current)
    @catalog = catalog
    @client = client || CatalogClientFactory.for(catalog)
    @now = now
  end

  def sync
    errors = []

    @client.namespaces.each do |namespace|
      begin
        @client.tables_in(namespace).each do |table_name|
          begin
            upsert_table(namespace, table_name)
          rescue StandardError => e
            errors << "#{namespace}.#{table_name}: #{e.message}"
            Rails.logger.warn("Sync failed for #{namespace}.#{table_name}: #{e.message}")
          end
        end
      rescue StandardError => e
        errors << "namespace #{namespace}: #{e.message}"
        Rails.logger.warn("Sync failed for namespace #{namespace}: #{e.message}")
      end
    end

    if errors.any?
      SlackAlert.notify("Sync of catalog #{@catalog.name} finished with #{errors.size} failure(s): " \
                        "#{errors.first(5).join('; ')}")
    end

    { errors: errors }
  end

  private

  def upsert_table(namespace, table_name)
    payload = @client.table_metadata(namespace, table_name)
    extractor = TableMetadataExtractor.new(payload["metadata"] || payload)

    table = @catalog.iceberg_tables.find_or_create_by!(namespace: namespace, name: table_name)
    health = HealthEvaluator.evaluate(extractor, plan: table.maintenance_plan, now: @now)

    attributes = {
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
      properties_json: extractor.properties
    }
    if health[:score]
      attributes[:health_score] = health[:score]
      attributes[:health_status] = health[:status].to_s
    end

    table.update!(attributes)
    table
  end
end
