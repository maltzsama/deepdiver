class CreateMaintenancePolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :maintenance_policies do |t|
      t.string :name,        null: false
      t.text   :description
      t.string :operation,   null: false
      t.string :cron,        null: false
      t.json   :config,      default: {}
      t.timestamps
    end
    add_index :maintenance_policies, :name, unique: true

    add_reference :maintenance_schedules, :maintenance_policy,
                  foreign_key: true, null: true
  end
end
