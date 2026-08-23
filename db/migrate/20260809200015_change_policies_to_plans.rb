class ChangePoliciesToPlans < ActiveRecord::Migration[8.1]
  def change
    remove_column :maintenance_policies, :operation, :string
    add_column :maintenance_policies, :steps_config, :json, default: {}
    # steps_config: { "optimize" => { "enabled" => true, "file_size_threshold" => "256MB" }, ... }
  end
end
