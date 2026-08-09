class AddScaleUpStartedAtToExecutionHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :execution_histories, :scale_up_started_at, :datetime
  end
end