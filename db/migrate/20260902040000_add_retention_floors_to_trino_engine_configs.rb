class AddRetentionFloorsToTrinoEngineConfigs < ActiveRecord::Migration[8.0]
  def change
    # The Trino-side retention FLOORS, which reject a maintenance step whose
    # own retention_threshold is shorter. Previously reachable only by typing
    # raw connector keys into the catalog's free-form properties JSON, with no
    # validation, no units and no discoverability (see #216).
    add_column :trino_engine_configs, :expire_snapshots_min_retention, :string,
               default: "7d", null: false
    add_column :trino_engine_configs, :remove_orphan_files_min_retention, :string,
               default: "7d", null: false
  end
end
