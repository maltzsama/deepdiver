class AddCadenceToMaintenanceSteps < ActiveRecord::Migration[8.1]
  def change
    # NULL = runs on every plan dispatch.
    # Filled = only runs when this cron also matches the instant.
    add_column :maintenance_steps, :cadence_cron, :string

    # Last instant the step actually ran - used so a window is not lost when
    # the previous dispatch was skipped for overlap.
    add_column :maintenance_steps, :last_run_at, :datetime
  end
end
