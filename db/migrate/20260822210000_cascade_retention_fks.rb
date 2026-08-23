class CascadeRetentionFks < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :execution_steps, :execution_histories
    add_foreign_key :execution_steps, :execution_histories, on_delete: :cascade

    remove_foreign_key :table_locks, :execution_histories
    add_foreign_key :table_locks, :execution_histories, on_delete: :cascade
  end
end
