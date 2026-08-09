class AddSnapshotsToIcebergTables < ActiveRecord::Migration[8.1]
  def change
    add_column :iceberg_tables, :snapshots_json, :json
  end
end
