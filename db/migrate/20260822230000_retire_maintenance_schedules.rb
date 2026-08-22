class RetireMaintenanceSchedules < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :execution_histories, :maintenance_schedules
    remove_column :execution_histories, :maintenance_schedule_id
    drop_table :maintenance_schedules
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
