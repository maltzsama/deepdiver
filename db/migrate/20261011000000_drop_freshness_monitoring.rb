# Removes the freshness monitoring feature: the probe/check/SLA tables and the
# freshness error events they produced. Generic ErrorEvents from other
# subsystems (catalog sync, engine, SSO, maintenance, retention) are kept.
class DropFreshnessMonitoring < ActiveRecord::Migration[8.1]
  def up
    # Purge only the freshness error events; generic ones stay.
    execute "DELETE FROM error_events WHERE operation = 'freshness-check'"

    drop_table :freshness_checks
    drop_table :freshness_runs
    drop_table :table_freshness_slas
  end

  def down
    create_table :table_freshness_slas do |t|
      t.references :iceberg_table, null: false, foreign_key: true
      t.boolean :enabled, default: false, null: false
      t.string :timestamp_column, null: false
      t.string :timestamp_type, default: "timestamp_tz", null: false
      t.string :source_timezone, default: "UTC", null: false
      t.string :partition_column
      t.integer :partition_lookback, default: 7, null: false
      t.integer :sla_minutes, default: 120, null: false
      t.integer :warning_at_percent, default: 80, null: false
      t.integer :warning_after_minutes, default: 180, null: false
      t.integer :severe_after_minutes, default: 360, null: false
      t.integer :critical_after_minutes, default: 720, null: false
      t.string :slack_channel
      t.string :slack_webhook_url
      t.string :email_to
      t.string :status, default: "unknown", null: false
      t.string :severity
      t.string :last_alert_level
      t.datetime :last_alert_at
      t.datetime :breached_since
      t.datetime :status_changed_at
      t.timestamps
    end
    add_index :table_freshness_slas, [ :iceberg_table_id ], unique: true,
              name: "index_table_freshness_slas_on_iceberg_table_id"
    add_index :table_freshness_slas, [ :enabled, :status ],
              name: "index_table_freshness_slas_on_enabled_and_status"

    create_table :freshness_runs do |t|
      t.string :status, default: "pending", null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :last_heartbeat_at
      t.integer :tables_checked, default: 0, null: false
      t.integer :tables_late, default: 0, null: false
      t.integer :tables_errored, default: 0, null: false
      t.text :error_message
      t.timestamps
    end
    add_index :freshness_runs, [ :status ], name: "index_freshness_runs_on_status"
    add_index :freshness_runs, [ :status, :last_heartbeat_at ],
              name: "index_freshness_runs_on_status_and_heartbeat"

    create_table :freshness_checks do |t|
      t.references :iceberg_table, null: false, foreign_key: true
      t.datetime :checked_at, null: false
      t.string :status, null: false
      t.integer :delay_seconds
      t.integer :sla_minutes
      t.datetime :max_timestamp
      t.integer :duration_ms
      t.string :trino_query_id
      t.text :error_message
      t.timestamps
    end
    add_index :freshness_checks, [ :iceberg_table_id, :checked_at ],
              name: "index_freshness_checks_on_iceberg_table_id_and_checked_at"
    add_index :freshness_checks, [ :checked_at ], name: "index_freshness_checks_on_checked_at"
    add_index :freshness_checks, [ :status, :checked_at ],
              name: "index_freshness_checks_on_status_and_checked_at"
  end
end
