class CreateFreshnessMonitoring < ActiveRecord::Migration[8.1]
  def change
    create_table :table_freshness_slas do |t|
      t.references :iceberg_table, null: false, foreign_key: true, index: { unique: true }

      t.boolean :enabled, null: false, default: false

      # --- watermark column ---
      t.string :timestamp_column, null: false

      # timestamp_tz | timestamp_ntz | epoch_seconds | epoch_millis | epoch_micros
      t.string :timestamp_type, null: false, default: "timestamp_tz"

      # Timezone in which the value was WRITTEN, for types that do not carry one.
      t.string :source_timezone, null: false, default: "UTC"

      # --- pruning ---
      t.string  :partition_column
      t.integer :partition_lookback, null: false, default: 7

      # --- SLA ---
      t.integer :sla_minutes, null: false, default: 120
      t.integer :warning_at_percent, null: false, default: 80

      # --- state and alerting ---
      t.string   :status, null: false, default: "unknown"
      t.datetime :status_changed_at
      t.datetime :breached_since
      t.datetime :last_alert_at
      t.string   :last_alert_level
      t.string   :slack_webhook_url

      t.timestamps
      t.index %i[enabled status]
    end

    # History: what answers "this table lags every Monday".
    create_table :freshness_checks do |t|
      t.references :iceberg_table, null: false, foreign_key: true
      t.datetime :checked_at,    null: false
      t.datetime :max_timestamp
      t.integer  :delay_seconds
      t.integer  :sla_minutes
      t.string   :status, null: false   # ok | warning | late | error | no_data
      t.text     :error_message
      t.string   :trino_query_id
      t.integer  :duration_ms
      t.timestamps
      t.index %i[iceberg_table_id checked_at]
      t.index %i[status checked_at]
    end

    # Engine demand coming from freshness - separate from maintenance runs.
    create_table :freshness_runs do |t|
      t.string   :status, null: false, default: "pending" # pending|running|finished|failed
      t.datetime :started_at
      t.datetime :finished_at
      t.integer  :tables_checked, null: false, default: 0
      t.integer  :tables_late,    null: false, default: 0
      t.integer  :tables_errored, null: false, default: 0
      t.text     :error_message
      t.timestamps
      t.index :status
    end
  end
end
