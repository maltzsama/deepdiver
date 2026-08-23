class AddHeartbeatToFreshnessRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :freshness_runs, :last_heartbeat_at, :datetime
    add_index :freshness_runs, %i[status last_heartbeat_at], name: "index_freshness_runs_on_status_and_heartbeat"
  end
end
