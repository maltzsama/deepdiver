# frozen_string_literal: true

class CreateMaintenanceSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :maintenance_schedules do |t|
      t.references :iceberg_table, null: false, foreign_key: true
      t.string :operation, null: false
      t.string :cron, null: false
      t.json :config, default: {}
      t.boolean :is_paused, null: false, default: false
      t.integer :consecutive_failures, null: false, default: 0

      t.timestamps
    end

    add_index :maintenance_schedules, %i[iceberg_table_id operation], unique: true
  end
end
