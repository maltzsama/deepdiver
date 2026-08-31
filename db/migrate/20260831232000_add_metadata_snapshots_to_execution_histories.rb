class AddMetadataSnapshotsToExecutionHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :execution_histories, :metadata_before, :json
    add_column :execution_histories, :metadata_after, :json
  end
end
