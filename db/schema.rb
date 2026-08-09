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

ActiveRecord::Schema[8.1].define(version: 2026_08_09_200005) do
  create_table "catalogs", force: :cascade do |t|
    t.string "catalog_type", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "name", null: false
    t.json "properties", default: {}
    t.string "trino_catalog_name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_catalogs_on_name", unique: true
  end

  create_table "execution_histories", force: :cascade do |t|
    t.boolean "awaiting_retry", default: false, null: false
    t.datetime "created_at", null: false
    t.string "current_step", default: "start", null: false
    t.text "error_message"
    t.integer "maintenance_schedule_id", null: false
    t.json "metrics"
    t.integer "retry_count", default: 0, null: false
    t.datetime "scale_up_started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["maintenance_schedule_id", "created_at"], name: "idx_on_maintenance_schedule_id_created_at_ba9b5c28dc"
    t.index ["maintenance_schedule_id"], name: "index_execution_histories_on_maintenance_schedule_id"
    t.index ["status"], name: "index_execution_histories_on_status"
  end

  create_table "iceberg_tables", force: :cascade do |t|
    t.integer "catalog_id", null: false
    t.datetime "created_at", null: false
    t.integer "health_score"
    t.string "health_status", default: "unknown", null: false
    t.datetime "last_data_update"
    t.string "name", null: false
    t.string "namespace", null: false
    t.datetime "updated_at", null: false
    t.index ["catalog_id", "namespace", "name"], name: "index_iceberg_tables_on_catalog_id_and_namespace_and_name", unique: true
    t.index ["catalog_id"], name: "index_iceberg_tables_on_catalog_id"
  end

  create_table "maintenance_policies", force: :cascade do |t|
    t.json "config", default: {}
    t.datetime "created_at", null: false
    t.string "cron", null: false
    t.text "description"
    t.string "name", null: false
    t.string "operation", null: false
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

  create_table "trino_locks", force: :cascade do |t|
    t.datetime "acquired_at"
    t.datetime "created_at", null: false
    t.bigint "execution_history_id"
    t.string "key", default: "global", null: false
    t.datetime "updated_at", null: false
    t.index ["execution_history_id"], name: "index_trino_locks_on_execution_history_id"
    t.index ["key"], name: "index_trino_locks_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "execution_histories", "maintenance_schedules"
  add_foreign_key "iceberg_tables", "catalogs"
  add_foreign_key "maintenance_schedules", "iceberg_tables"
  add_foreign_key "maintenance_schedules", "maintenance_policies"
end
