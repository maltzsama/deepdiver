class AddMissingIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :execution_histories, :created_at
    add_index :freshness_checks, :checked_at
    add_index :error_events, %i[status last_seen_at]
    add_index :execution_steps, :trino_query_id
  end
end
