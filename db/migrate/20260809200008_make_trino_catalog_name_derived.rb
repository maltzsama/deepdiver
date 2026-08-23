class MakeTrinoCatalogNameDerived < ActiveRecord::Migration[8.1]
  def up
    change_column_null :catalogs, :trino_catalog_name, true
    rename_column :catalogs, :trino_catalog_name, :trino_catalog_name_override
  end

  def down
    rename_column :catalogs, :trino_catalog_name_override, :trino_catalog_name
    execute "UPDATE catalogs SET trino_catalog_name = name WHERE trino_catalog_name IS NULL"
    change_column_null :catalogs, :trino_catalog_name, false
  end
end
