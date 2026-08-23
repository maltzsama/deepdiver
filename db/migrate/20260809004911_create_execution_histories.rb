# frozen_string_literal: true

class CreateExecutionHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :execution_histories do |t|
      t.references :maintenance_schedule, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :current_step, null: false, default: "start"
      t.integer :retry_count, null: false, default: 0
      t.text :error_message
      t.json :metrics

      t.timestamps
    end

    add_index :execution_histories, :status
    add_index :execution_histories, %i[maintenance_schedule_id created_at]
  end
end
