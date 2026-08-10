module MaintenancePlansHelper
  # Human "next run" for the edit form's cron preview.
  def plan_next_fire(plan)
    parsed = Fugit::Cron.parse(plan.cron)
    return t("plans.edit.next_fires_invalid") if parsed.nil?

    l(parsed.next_time(Time.current).to_t, format: :long)
  end

  # Which config key the step's threshold field maps to, or nil when the step
  # takes no threshold parameter.
  def step_threshold_name(operation)
    case operation
    when "optimize"            then "file_size_threshold"
    when "expire_snapshots", "remove_orphan_files" then "retention_threshold"
    end
  end

  def step_threshold_placeholder(operation)
    step_threshold_name(operation) == "file_size_threshold" ? "128MB" : "7d"
  end
end
