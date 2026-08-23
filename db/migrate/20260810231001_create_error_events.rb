class CreateErrorEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :error_events do |t|
      t.references :catalog, foreign_key: true
      t.string :schema, null: false, default: ""
      t.string :table, null: false, default: ""
      t.string :operation, null: false, default: "catalog-sync"
      t.string :source_system, null: false, default: "deeplake"
      t.string :error_class, null: false, default: "StandardError"
      t.string :message, null: false, default: ""
      t.string :severity, null: false, default: "error"
      t.string :status, null: false, default: "open"
      t.json :context, default: {}
      t.string :source_column
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.integer :occurrence_count, null: false, default: 1

      t.timestamps
    end

    add_index :error_events, [ :catalog_id, :status ]
    add_index :error_events, [ :operation, :status ]
    add_index :error_events, [ :schema, :table ]
  end
end
