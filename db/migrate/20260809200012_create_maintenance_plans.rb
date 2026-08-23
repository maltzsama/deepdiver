class CreateMaintenancePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :maintenance_plans do |t|
      t.references :iceberg_table, null: false, foreign_key: true, index: { unique: true }
      t.references :maintenance_policy, foreign_key: true

      t.string  :cron, null: false
      t.boolean :is_paused, null: false, default: false
      t.integer :consecutive_failures, null: false, default: 0
      t.integer :auto_pause_after, null: false, default: 3

      # Marked when the legacy-schedule migration had to pick a cron among
      # several. Clears when someone reviews it.
      t.boolean :needs_review, null: false, default: false

      t.timestamps
    end

    create_table :maintenance_steps do |t|
      t.references :maintenance_plan, null: false, foreign_key: true
      t.string  :operation, null: false
      t.integer :position,  null: false
      t.boolean :enabled,   null: false, default: true
      t.json    :config,    default: {}
      t.timestamps

      t.index %i[maintenance_plan_id operation], unique: true
      t.index %i[maintenance_plan_id position],  unique: true
    end

    # An execution now runs a CHAIN, not a single operation.
    add_reference :execution_histories, :maintenance_plan, foreign_key: true
    add_column :execution_histories, :started_at,  :datetime
    add_column :execution_histories, :finished_at, :datetime

    create_table :execution_steps do |t|
      t.references :execution_history, null: false, foreign_key: true
      t.references :maintenance_step,  foreign_key: true

      t.string :operation, null: false
      t.string :status,    null: false, default: "pending"
      # pending | running | succeeded | failed | skipped

      t.datetime :started_at
      t.datetime :finished_at
      t.integer  :retry_count, null: false, default: 0
      t.text     :error_message
      t.string   :trino_query_id
      t.json     :metrics, default: {}

      t.timestamps
      t.index %i[execution_history_id operation], unique: true
    end
  end
end
