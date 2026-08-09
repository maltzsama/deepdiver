class AddAwaitingRetryToExecutionHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :execution_histories, :awaiting_retry, :boolean, null: false, default: false
  end
end