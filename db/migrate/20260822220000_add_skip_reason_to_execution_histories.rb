class AddSkipReasonToExecutionHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :execution_histories, :skip_reason, :string
  end
end
