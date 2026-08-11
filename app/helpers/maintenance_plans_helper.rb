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

  # Which config key the step's threshold field maps to, or nil when the step
  # takes no threshold parameter.
  # @param operation [String] the maintenance step operation name.
  # @return [String, nil] the config key, or nil when the step has no threshold.
  def step_threshold_name(operation)
    case operation
    when "optimize"            then "file_size_threshold"
    when "expire_snapshots", "remove_orphan_files" then "retention_threshold"
    end
  end

  # Returns the placeholder text for a step's threshold field based on whether
  # the threshold is a file size or a retention period.
  # @param operation [String] the maintenance step operation name.
  # @return [String] "128MB" for size thresholds, "7d" otherwise.
  def step_threshold_placeholder(operation)
    step_threshold_name(operation) == "file_size_threshold" ? "128MB" : "7d"
  end
end
