class AddIcebergTablesCountToCatalogs < ActiveRecord::Migration[8.1]
  def change
    add_column :catalogs, :iceberg_tables_count, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE catalogs
          SET iceberg_tables_count = (
            SELECT COUNT(*) FROM iceberg_tables WHERE iceberg_tables.catalog_id = catalogs.id
          )
        SQL
      end
    end
  end
end
