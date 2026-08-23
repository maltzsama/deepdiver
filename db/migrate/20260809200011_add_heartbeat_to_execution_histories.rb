class AddHeartbeatToExecutionHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :execution_histories, :last_heartbeat_at, :datetime
    add_index  :execution_histories, %i[status last_heartbeat_at]
  end
end
