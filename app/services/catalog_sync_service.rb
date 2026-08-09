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
    @client.namespaces.each do |namespace|
      @client.tables_in(namespace).each do |table_name|
        upsert_table(namespace, table_name)
      end
    end
  end

  private

  def upsert_table(namespace, table_name)
    payload = @client.table_metadata(namespace, table_name)
    extractor = TableMetadataExtractor.new(payload["metadata"] || payload)
    health = HealthEvaluator.evaluate(extractor, now: @now)

    table = @catalog.iceberg_tables.find_or_create_by!(namespace: namespace, name: table_name)

    attributes = { last_data_update: extractor.last_snapshot_at }
    if health[:score]
      attributes[:health_score] = health[:score]
      attributes[:health_status] = health[:status].to_s
    end

    table.update!(attributes)
    table
  end
end
