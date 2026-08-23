# frozen_string_literal: true

class CreateIcebergTables < ActiveRecord::Migration[8.1]
  def change
    create_table :iceberg_tables do |t|
      t.references :catalog, null: false, foreign_key: true
      t.string :namespace, null: false
      t.string :name, null: false
      t.datetime :last_data_update
      t.integer :health_score
      t.string :health_status, null: false, default: "unknown"

      t.timestamps
    end

    add_index :iceberg_tables, %i[catalog_id namespace name], unique: true
  end
end
