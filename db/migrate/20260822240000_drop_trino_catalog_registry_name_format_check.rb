class DropTrinoCatalogRegistryNameFormatCheck < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :trino_catalog_registry, name: "trino_catalog_registry_name_format"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
