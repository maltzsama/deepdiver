class AddSoftDeleteAndUuidIdentityToIcebergTables < ActiveRecord::Migration[8.1]
  def change
    # Soft delete: a table dropped in the catalog stays recorded but inactive,
    # preserving its history until further notice.
    add_column :iceberg_tables, :active, :boolean, null: false, default: true
    add_column :iceberg_tables, :deactivated_at, :datetime

    # Identity comes from the catalog's table-uuid, not the (namespace, name)
    # pair: a dropped table that reappears is a NEW table (new uuid), so a
    # partial unique index on (catalog_id, table_uuid) is the real constraint.
    # The composite index stays for lookups but is no longer unique.
    remove_index :iceberg_tables, name: "index_iceberg_tables_on_catalog_id_and_namespace_and_name"
    add_index :iceberg_tables, %i[catalog_id namespace name],
              name: "index_iceberg_tables_on_catalog_id_and_namespace_and_name"
    add_index :iceberg_tables, %i[catalog_id table_uuid], unique: true,
              name: "index_iceberg_tables_on_catalog_id_and_table_uuid", where: "table_uuid IS NOT NULL"
  end
end
