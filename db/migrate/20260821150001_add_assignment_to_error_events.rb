class AddAssignmentToErrorEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :error_events, :assigned_to, foreign_key: { to_table: :users }, null: true
    add_reference :error_events, :assigned_by, foreign_key: { to_table: :users }, null: true
    add_column :error_events, :acknowledged_at, :datetime
    add_column :error_events, :resolved_at, :datetime
  end
end
