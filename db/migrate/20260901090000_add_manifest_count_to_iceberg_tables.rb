class AddManifestCountToIcebergTables < ActiveRecord::Migration[8.0]
  def change
    add_column :iceberg_tables, :manifest_count, :integer
  end
end
