# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_12_110000) do
  create_table "alert_channels", force: :cascade do |t|
    t.integer "cooldown_minutes", default: 60, null: false
    t.datetime "created_at", null: false
    t.string "email_to"
    t.boolean "enabled", default: true, null: false
    t.string "last_error"
    t.datetime "last_sent_at"
    t.text "message_template"
    t.string "min_severity", default: "warning", null: false
    t.string "name", null: false
    t.string "slack_channel"
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_alert_channels_on_enabled"
  end

  create_table "alert_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "slack_webhook_url"
    t.string "smtp_address"
    t.string "smtp_from"
    t.string "smtp_password"
    t.integer "smtp_port"
    t.string "smtp_user_name"
    t.datetime "updated_at", null: false
  end

  create_table "catalog_credentials", force: :cascade do |t|
    t.string "auth_method", default: "none", null: false
    t.integer "catalog_id", null: false
    t.string "client_id"
    t.datetime "created_at", null: false
    t.string "scope", default: "PRINCIPAL_ROLE:ALL"
    t.text "secret"
    t.string "secret_hint"
    t.datetime "secret_set_at"
    t.string "token_path", default: "/v1/oauth/tokens"
    t.datetime "updated_at", null: false
    t.text "verification_error"
    t.datetime "verified_at"
    t.index ["catalog_id"], name: "index_catalog_credentials_on_catalog_id", unique: true
  end

  create_table "catalogs", force: :cascade do |t|
    t.string "catalog_type", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.integer "iceberg_tables_count", default: 0, null: false
    t.string "name", null: false
    t.json "properties", default: {}
    t.string "trino_catalog_name_override"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_catalogs_on_name", unique: true
  end

  create_table "error_events", force: :cascade do |t|
    t.integer "catalog_id"
    t.json "context", default: {}
    t.datetime "created_at", null: false
    t.string "error_class", default: "StandardError", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.string "message", default: "", null: false
    t.integer "occurrence_count", default: 1, null: false
    t.string "operation", default: "catalog-sync", null: false
    t.string "schema", default: "", null: false
    t.string "severity", default: "error", null: false
    t.string "source_column"
    t.string "source_system", default: "deeplake", null: false
    t.string "status", default: "open", null: false
    t.string "table", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_id", "status"], name: "index_error_events_on_catalog_id_and_status"
    t.index ["catalog_id"], name: "index_error_events_on_catalog_id"
    t.index ["operation", "status"], name: "index_error_events_on_operation_and_status"
    t.index ["schema", "table"], name: "index_error_events_on_schema_and_table"
  end

  create_table "execution_histories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "current_step", default: "start", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "iceberg_table_id", null: false
    t.datetime "last_heartbeat_at"
    t.integer "maintenance_plan_id"
    t.integer "maintenance_schedule_id"
    t.json "metrics"
    t.integer "retry_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["iceberg_table_id"], name: "index_execution_histories_on_iceberg_table_id"
    t.index ["maintenance_plan_id"], name: "index_execution_histories_on_maintenance_plan_id"
    t.index ["maintenance_schedule_id", "created_at"], name: "idx_on_maintenance_schedule_id_created_at_ba9b5c28dc"
    t.index ["maintenance_schedule_id"], name: "index_execution_histories_on_maintenance_schedule_id"
    t.index ["status", "last_heartbeat_at"], name: "index_execution_histories_on_status_and_last_heartbeat_at"
    t.index ["status"], name: "index_execution_histories_on_status"
  end

  create_table "execution_steps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "execution_history_id", null: false
    t.datetime "finished_at"
    t.integer "maintenance_step_id"
    t.json "metrics", default: {}
    t.string "operation", null: false
    t.integer "retry_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "trino_query_id"
    t.datetime "updated_at", null: false
    t.index ["execution_history_id", "operation"], name: "index_execution_steps_on_execution_history_id_and_operation", unique: true
    t.index ["execution_history_id"], name: "index_execution_steps_on_execution_history_id"
    t.index ["maintenance_step_id"], name: "index_execution_steps_on_maintenance_step_id"
  end

  create_table "freshness_checks", force: :cascade do |t|
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.integer "delay_seconds"
    t.integer "duration_ms"
    t.text "error_message"
    t.integer "iceberg_table_id", null: false
    t.datetime "max_timestamp"
    t.integer "sla_minutes"
    t.string "status", null: false
    t.string "trino_query_id"
    t.datetime "updated_at", null: false
    t.index ["iceberg_table_id", "checked_at"], name: "index_freshness_checks_on_iceberg_table_id_and_checked_at"
    t.index ["iceberg_table_id"], name: "index_freshness_checks_on_iceberg_table_id"
    t.index ["status", "checked_at"], name: "index_freshness_checks_on_status_and_checked_at"
  end

  create_table "freshness_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "tables_checked", default: 0, null: false
    t.integer "tables_errored", default: 0, null: false
    t.integer "tables_late", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_freshness_runs_on_status"
  end

  create_table "iceberg_tables", force: :cascade do |t|
    t.integer "catalog_id", null: false
    t.datetime "created_at", null: false
    t.bigint "equality_deletes"
    t.integer "health_score"
    t.string "health_status", default: "unknown", null: false
    t.datetime "health_status_changed_at"
    t.datetime "last_data_update"
    t.datetime "metadata_synced_at"
    t.string "name", null: false
    t.string "namespace", null: false
    t.datetime "oldest_snapshot_at"
    t.json "partition_json"
    t.bigint "position_deletes"
    t.json "properties_json"
    t.json "refs_json"
    t.json "schema_json"
    t.integer "snapshot_count"
    t.json "snapshots_json"
    t.string "storage_location"
    t.string "table_uuid"
    t.bigint "total_data_files"
    t.bigint "total_records"
    t.bigint "total_size_bytes"
    t.datetime "updated_at", null: false
    t.index ["catalog_id", "namespace", "name"], name: "index_iceberg_tables_on_catalog_id_and_namespace_and_name", unique: true
    t.index ["catalog_id"], name: "index_iceberg_tables_on_catalog_id"
    t.index ["health_status", "health_status_changed_at"], name: "idx_on_health_status_health_status_changed_at_0caff44fb9"
    t.index ["total_data_files"], name: "index_iceberg_tables_on_total_data_files"
    t.index ["total_size_bytes"], name: "index_iceberg_tables_on_total_size_bytes"
  end

  create_table "maintenance_plans", force: :cascade do |t|
    t.integer "auto_pause_after", default: 3, null: false
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "cron", null: false
    t.integer "iceberg_table_id", null: false
    t.boolean "is_paused", default: false, null: false
    t.integer "maintenance_policy_id"
    t.boolean "needs_review", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["iceberg_table_id"], name: "index_maintenance_plans_on_iceberg_table_id", unique: true
    t.index ["maintenance_policy_id"], name: "index_maintenance_plans_on_maintenance_policy_id"
  end

  create_table "maintenance_policies", force: :cascade do |t|
    t.json "config", default: {}
    t.datetime "created_at", null: false
    t.string "cron", null: false
    t.text "description"
    t.string "name", null: false
    t.json "steps_config", default: {}
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_maintenance_policies_on_name", unique: true
  end

  create_table "maintenance_schedules", force: :cascade do |t|
    t.json "config", default: {}
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "cron", null: false
    t.integer "iceberg_table_id", null: false
    t.boolean "is_paused", default: false, null: false
    t.integer "maintenance_policy_id"
    t.string "operation", null: false
    t.datetime "updated_at", null: false
    t.index ["iceberg_table_id", "operation"], name: "index_maintenance_schedules_on_iceberg_table_id_and_operation", unique: true
    t.index ["iceberg_table_id"], name: "index_maintenance_schedules_on_iceberg_table_id"
    t.index ["maintenance_policy_id"], name: "index_maintenance_schedules_on_maintenance_policy_id"
  end

  create_table "maintenance_steps", force: :cascade do |t|
    t.string "cadence_cron"
    t.json "config", default: {}
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_run_at"
    t.integer "maintenance_plan_id", null: false
    t.string "operation", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["maintenance_plan_id", "operation"], name: "index_maintenance_steps_on_maintenance_plan_id_and_operation", unique: true
    t.index ["maintenance_plan_id", "position"], name: "index_maintenance_steps_on_maintenance_plan_id_and_position", unique: true
    t.index ["maintenance_plan_id"], name: "index_maintenance_steps_on_maintenance_plan_id"
  end

  create_table "role_change_logs", force: :cascade do |t|
    t.integer "changed_by_id", null: false
    t.datetime "created_at", null: false
    t.integer "from_role", null: false
    t.string "reason"
    t.integer "to_role", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["changed_by_id"], name: "index_role_change_logs_on_changed_by_id"
    t.index ["user_id"], name: "index_role_change_logs_on_user_id"
  end

  create_table "table_freshness_slas", force: :cascade do |t|
    t.datetime "breached_since"
    t.datetime "created_at", null: false
    t.integer "critical_after_minutes", default: 720, null: false
    t.boolean "enabled", default: false, null: false
    t.integer "iceberg_table_id", null: false
    t.datetime "last_alert_at"
    t.string "last_alert_level"
    t.string "partition_column"
    t.integer "partition_lookback", default: 7, null: false
    t.integer "severe_after_minutes", default: 360, null: false
    t.string "severity"
    t.integer "sla_minutes", default: 120, null: false
    t.string "slack_webhook_url"
    t.string "source_timezone", default: "UTC", null: false
    t.string "status", default: "unknown", null: false
    t.datetime "status_changed_at"
    t.string "timestamp_column", null: false
    t.string "timestamp_type", default: "timestamp_tz", null: false
    t.datetime "updated_at", null: false
    t.integer "warning_after_minutes", default: 180, null: false
    t.integer "warning_at_percent", default: 80, null: false
    t.index ["enabled", "status"], name: "index_table_freshness_slas_on_enabled_and_status"
    t.index ["iceberg_table_id"], name: "index_table_freshness_slas_on_iceberg_table_id", unique: true
  end

  create_table "table_locks", force: :cascade do |t|
    t.datetime "acquired_at", null: false
    t.datetime "created_at", null: false
    t.integer "execution_history_id", null: false
    t.integer "iceberg_table_id", null: false
    t.datetime "updated_at", null: false
    t.index ["execution_history_id"], name: "index_table_locks_on_execution_history_id"
    t.index ["iceberg_table_id"], name: "index_table_locks_on_iceberg_table_id", unique: true
  end

  create_table "team_catalog_scopes", force: :cascade do |t|
    t.integer "catalog_id", null: false
    t.datetime "created_at", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_id"], name: "index_team_catalog_scopes_on_catalog_id"
    t.index ["team_id", "catalog_id"], name: "index_team_catalog_scopes_on_team_id_and_catalog_id", unique: true
    t.index ["team_id"], name: "index_team_catalog_scopes_on_team_id"
  end

  create_table "team_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["team_id", "user_id"], name: "index_team_memberships_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_teams_on_name", unique: true
  end

  create_table "trino_catalog_registry", primary_key: ["cluster_id", "catalog_name"], force: :cascade do |t|
    t.string "catalog_name", null: false
    t.string "catalog_version"
    t.string "cluster_id", null: false
    t.string "connector_name", null: false
    t.boolean "enabled", default: true, null: false
    t.json "properties", null: false
    t.text "sync_error"
    t.string "sync_status", default: "pending", null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.string "updated_by", default: "baleia", null: false
    t.index ["cluster_id"], name: "trino_catalog_registry_cluster_enabled_idx", where: "enabled"
    t.check_constraint "catalog_name GLOB '[a-z][a-z0-9_]*' AND length(catalog_name) <= 63\n     AND catalog_name NOT IN ('system', 'jmx', 'tpch', 'tpcds', 'memory')\n     AND connector_name GLOB '[a-z][a-z0-9_]*' AND length(connector_name) <= 63", name: "trino_catalog_registry_name_format"
    t.check_constraint "sync_status IN ('pending', 'synced', 'error')", name: "trino_catalog_registry_sync_status_format"
  end

  create_table "trino_clusters", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_trino_clusters_on_name", unique: true
  end

  create_table "trino_engine_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "drain_started_at"
    t.bigint "generation", default: 0, null: false
    t.text "last_error"
    t.integer "start_attempts", default: 0, null: false
    t.string "status", default: "down", null: false
    t.datetime "status_changed_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: ""
    t.datetime "invited_at"
    t.bigint "invited_by_id"
    t.datetime "last_seen_at"
    t.string "locale", default: "en", null: false
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.string "status", default: "active", null: false
    t.datetime "suspended_at"
    t.bigint "suspended_by_id"
    t.string "theme", default: "dark", null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["status"], name: "index_users_on_status"
  end

  add_foreign_key "catalog_credentials", "catalogs"
  add_foreign_key "error_events", "catalogs"
  add_foreign_key "execution_histories", "iceberg_tables"
  add_foreign_key "execution_histories", "maintenance_plans"
  add_foreign_key "execution_histories", "maintenance_schedules"
  add_foreign_key "execution_steps", "execution_histories"
  add_foreign_key "execution_steps", "maintenance_steps"
  add_foreign_key "freshness_checks", "iceberg_tables"
  add_foreign_key "iceberg_tables", "catalogs"
  add_foreign_key "maintenance_plans", "iceberg_tables"
  add_foreign_key "maintenance_plans", "maintenance_policies"
  add_foreign_key "maintenance_schedules", "iceberg_tables"
  add_foreign_key "maintenance_schedules", "maintenance_policies"
  add_foreign_key "maintenance_steps", "maintenance_plans"
  add_foreign_key "role_change_logs", "users"
  add_foreign_key "role_change_logs", "users", column: "changed_by_id"
  add_foreign_key "table_freshness_slas", "iceberg_tables"
  add_foreign_key "table_locks", "execution_histories"
  add_foreign_key "table_locks", "iceberg_tables"
  add_foreign_key "team_catalog_scopes", "catalogs"
  add_foreign_key "team_catalog_scopes", "teams"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "team_memberships", "users"
  add_foreign_key "trino_catalog_registry", "trino_clusters", column: "cluster_id"
  add_foreign_key "users", "users", column: "invited_by_id"
  add_foreign_key "users", "users", column: "suspended_by_id"
end
