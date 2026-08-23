class RewriteCatalogPropertiesToReferences < ActiveRecord::Migration[8.1]
  def up
    TrinoCatalogProjection.new.sync_all!
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
