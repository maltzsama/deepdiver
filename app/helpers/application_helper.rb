module ApplicationHelper
  HEALTH_BADGE = {
    "healthy"  => "badge-healthy",
    "warning"  => "badge-warning",
    "critical" => "badge-critical",
    "unknown"  => "badge-unknown"
  }.freeze

  STATUS_BADGE = {
    "success" => "badge-healthy",
    "failed"  => "badge-critical",
    "running" => "badge-running",
    "pending" => "badge-neutral"
  }.freeze

  def health_badge_class(status)
    HEALTH_BADGE.fetch(status.to_s, "badge-unknown")
  end

  def execution_status_badge_class(status)
    STATUS_BADGE.fetch(status.to_s, "badge-neutral")
  end

  def strata_fill_class(status)
    case status.to_s
    when "healthy"  then "strata-fill-healthy"
    when "critical" then "strata-fill-critical"
    else "strata-fill-warning"
    end
  end

  STEP_LABELS = {
    "start"         => "lock",
    "scale_up"      => "scale up",
    "executing_sql" => "SQL",
    "scale_down"    => "scale down",
    "done"          => "done"
  }.freeze

  def step_label(step)
    STEP_LABELS.fetch(step.to_s, step.to_s)
  end

  # Visual state of an execution, including the retry created for commit
  # conflicts. Returns :retrying, :failed or :running.
  def execution_visual_state(execution)
    return :failed if execution.status == "failed"
    return :retrying if execution.respond_to?(:awaiting_retry) && execution.awaiting_retry?

    :running
  end

  def nav_link_to(label, path, active_when:)
    classes = [ "app-nav-link" ]
    classes << "app-nav-link-active" if active_when
    link_to label, path, class: classes.join(" ")
  end

  def timestamp(value)
    return content_tag(:span, "—", class: "cell-muted") if value.blank?

    content_tag(:span, value.to_fs(:db), class: "cell-num", title: value.iso8601)
  end
end
