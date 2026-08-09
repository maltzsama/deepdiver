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

  def execution_step_badge_class(status)
    case status.to_s
    when "succeeded" then "badge-healthy"
    when "failed"    then "badge-critical"
    when "running"   then "badge-running"
    else "badge-neutral"
    end
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

  # Visual state of an execution. Returns :retrying, :failed or :running.
  # A running execution with a positive retry count is waiting for the next
  # commit-conflict attempt - its own demand keeps the engine up.
  def execution_visual_state(execution)
    return :failed if execution.status == "failed"
    return :retrying if execution.status == "running" && execution.retry_count.positive?

    :running
  end

  def nav_link_to(label, path, active_when:)
    classes = [ "app-nav-link" ]
    classes << "app-nav-link-active" if active_when
    if block_given?
      link_to path, class: classes.join(" ") do
        yield
      end
    else
      link_to label, path, class: classes.join(" ")
    end
  end

  def duration_label(seconds)
    return nil if seconds.nil?

    seconds = seconds.to_i
    if seconds < 60
      "#{seconds}s"
    elsif seconds < 3600
      "#{(seconds / 60).round} min"
    else
      "#{(seconds / 3600.0).round(1)} h"
    end
  end

  def timestamp(value)
    return content_tag(:span, "—", class: "cell-muted") if value.blank?

    content_tag(:span, value.to_fs(:db), class: "cell-num", title: value.iso8601)
  end

  # Concise composition summary for the health tooltip in the tables list.
  def table_health_tooltip(table)
    parts = []
    if (avg = table.average_file_size)
      parts << "avg file #{number_to_human_size(avg)}"
    end
    parts << "#{table.snapshot_count} snapshots" if table.snapshot_count
    deletes = [ table.position_deletes, table.equality_deletes ].compact.sum
    parts << "#{number_to_human(deletes)} deletes / #{number_to_human(table.total_records)} records" if deletes.positive?
    parts.any? ? parts.join(" · ") : t("health.no_data")
  end
end
