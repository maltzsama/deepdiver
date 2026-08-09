class AllowPlanOnlyExecutions < ActiveRecord::Migration[8.1]
  def change
    change_column_null :execution_histories, :maintenance_schedule_id, true
  end
end
