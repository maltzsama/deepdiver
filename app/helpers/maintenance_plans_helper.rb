# View helpers for the maintenance plans screens, covering the cron preview
# and the step configuration form.
module MaintenancePlansHelper
  # Human "next run" for the edit form's cron preview.
  # @param plan [MaintenancePlan] the plan whose cron is previewed.
  # @return [String] the localised next run time, or an invalid-cron message.
  def plan_next_fire(plan)
    parsed = Fugit::Cron.parse(plan.cron)
    return t("plans.edit.next_fires_invalid") if parsed.nil?

    l(parsed.next_time(Time.current).to_t, format: :long)
  end

  # Which config keys the step's form renders, per operation.
  #
  # @param operation [String] the maintenance step operation name.
  # @return [Array<String>] the config keys shown in the form.
  def step_config_fields(operation)
    case operation
    when "optimize"            then %w[file_size_threshold where]
    when "expire_snapshots"    then %w[retention_threshold snapshot_ids]
    when "remove_orphan_files" then %w[retention_threshold]
    else []
    end
  end

  # The label for a step config key.
  #
  # @param key [String] the config key.
  # @return [String] the i18n label.
  def step_config_label(key)
    t("plans.edit.config_#{key}")
  end

  # The placeholder for a step config key.
  #
  # @param key [String] the config key.
  # @return [String] the placeholder text.
  def step_config_placeholder(key)
    case key
    when "file_size_threshold" then "128MB"
    when "retention_threshold" then "7d"
    when "snapshot_ids" then "123456789, 987654321"
    when "where" then "event_hour >= current_timestamp() - INTERVAL 2 HOUR"
    end
  end
end
