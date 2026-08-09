# frozen_string_literal: true

class CreateTrinoLocks < ActiveRecord::Migration[8.1]
  def change
    create_table :trino_locks do |t|
      t.string :key, null: false, default: "global"
      t.string :owner
      t.bigint :execution_history_id
      t.datetime :acquired_at

      t.timestamps
    end

    add_index :trino_locks, :key, unique: true
    add_index :trino_locks, :execution_history_id
  end
end
