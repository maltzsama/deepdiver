class AddSoftDeleteToMaintenancePlans < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenance_plans, :deleted_at, :datetime

    # One active plan per table, but a soft-deleted (discarded) plan must not
    # block a fresh one for the same table — hence the partial index.
    remove_index :maintenance_plans, :iceberg_table_id
    add_index :maintenance_plans, :iceberg_table_id,
              unique: true,
              where: "deleted_at IS NULL",
              name: "index_maintenance_plans_on_iceberg_table_id_kept"
  end
end
