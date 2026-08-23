class AddTrinoCatalogNameToCatalogs < ActiveRecord::Migration[8.1]
  def up
    add_column :catalogs, :trino_catalog_name, :string
    execute "UPDATE catalogs SET trino_catalog_name = name WHERE trino_catalog_name IS NULL"
    change_column_null :catalogs, :trino_catalog_name, false
  end

  def down
    remove_column :catalogs, :trino_catalog_name
  end
end
