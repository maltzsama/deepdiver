class CreateTrinoEngineConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :trino_engine_configs do |t|
      t.string  :topology, null: false, default: "cluster"
      t.integer :worker_replicas, null: false, default: 2
      t.string  :coordinator_cpu, null: false, default: "2"
      t.string  :coordinator_memory, null: false, default: "2Gi"
      t.string  :worker_cpu, null: false, default: "1"
      t.string  :worker_memory, null: false, default: "2Gi"

      t.timestamps
    end
  end
end
