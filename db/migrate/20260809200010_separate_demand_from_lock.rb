class SeparateDemandFromLock < ActiveRecord::Migration[8.1]
  def change
    # Exclusivity per TABLE, not global. A single coordinator still runs one
    # maintenance at a time, but per-table is the correct rule and survives
    # when parallelism arrives.
    create_table :table_locks do |t|
      t.references :iceberg_table,     null: false, foreign_key: true, index: { unique: true }
      t.references :execution_history, null: false, foreign_key: true
      t.datetime   :acquired_at,       null: false
      t.timestamps
    end

    # Engine state: a single row.
    create_table :trino_engine_states do |t|
      t.string   :status, null: false, default: "down"
      # down | starting | up | draining | failed
      t.datetime :status_changed_at, null: false
      t.datetime :drain_started_at
      t.integer  :start_attempts, null: false, default: 0
      t.text     :last_error
      t.timestamps
    end

    # The table lock resolves the table directly; backfill from the schedule.
    add_reference :execution_histories, :iceberg_table, foreign_key: true, index: true
    execute <<~SQL
      UPDATE execution_histories
      SET iceberg_table_id = (
        SELECT maintenance_schedules.iceberg_table_id
        FROM maintenance_schedules
        WHERE maintenance_schedules.id = execution_histories.maintenance_schedule_id
      )
    SQL
    change_column_null :execution_histories, :iceberg_table_id, false

    # awaiting_retry is gone: an execution waiting to retry is active demand
    # like any other, and the engine stays up on its own.
    remove_column :execution_histories, :awaiting_retry, :boolean

    # The startup time belongs to the engine, not to an execution.
    remove_column :execution_histories, :scale_up_started_at, :datetime

    drop_table :trino_locks
  end
end
