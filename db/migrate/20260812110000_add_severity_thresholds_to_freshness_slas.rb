class AddSeverityThresholdsToFreshnessSlas < ActiveRecord::Migration[8.1]
  def change
    # Progressive severity bands (in minutes of absolute delay), configurable
    # per SLA because the SLA budget itself is per table. Defaults keep the
    # original 3h/6h/12h behaviour.
    add_column :table_freshness_slas, :warning_after_minutes,  :integer, null: false, default: 180
    add_column :table_freshness_slas, :severe_after_minutes,   :integer, null: false, default: 360
    add_column :table_freshness_slas, :critical_after_minutes, :integer, null: false, default: 720
  end
end
