class UnifyTrinoLockOwner < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE trino_locks
      SET execution_history_id = CAST(owner AS INTEGER)
      WHERE owner IS NOT NULL AND execution_history_id IS NULL
    SQL
    remove_column :trino_locks, :owner
  end

  def down
    add_column :trino_locks, :owner, :string
    execute "UPDATE trino_locks SET owner = CAST(execution_history_id AS TEXT)"
  end
end
