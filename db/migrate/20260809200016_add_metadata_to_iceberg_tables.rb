class AddMetadataToIcebergTables < ActiveRecord::Migration[8.1]
  def change
    add_column :iceberg_tables, :table_uuid,        :string
    add_column :iceberg_tables, :storage_location,  :string
    add_column :iceberg_tables, :total_records,     :bigint
    add_column :iceberg_tables, :total_data_files,  :bigint
    add_column :iceberg_tables, :total_size_bytes,  :bigint
    add_column :iceberg_tables, :position_deletes,  :bigint
    add_column :iceberg_tables, :equality_deletes,  :bigint
    add_column :iceberg_tables, :snapshot_count,    :integer
    add_column :iceberg_tables, :oldest_snapshot_at, :datetime
    add_column :iceberg_tables, :metadata_synced_at, :datetime

    # Large payloads stay out of the hot columns: the global list does not
    # need them, and they are only used on the table screen.
    add_column :iceberg_tables, :schema_json,   :json
    add_column :iceberg_tables, :partition_json, :json
    add_column :iceberg_tables, :refs_json,     :json
    add_column :iceberg_tables, :properties_json, :json

    add_index :iceberg_tables, :total_data_files
    add_index :iceberg_tables, :total_size_bytes
  end
end
