class AddActiveExecutionUniquePerTable < ActiveRecord::Migration[8.0]
  def change
    # At most one pending/running execution per table (see #206). The partial
    # index enforces what run_plan's read-then-write check only claims: two
    # dispatches that interleave both pass the .first query, so without this
    # they both create a pending execution and one resolves to a spurious
    # 'skipped'. Mirrors the singleton constraints from #175.
    add_index :execution_histories, :iceberg_table_id,
              unique: true,
              where: "status IN ('pending','running')",
              name: "index_execution_histories_active_per_table"
  end
end