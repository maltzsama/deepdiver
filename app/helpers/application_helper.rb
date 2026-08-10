module ApplicationHelper
  def health_badge_class(status)
    case status.to_s
    when "healthy"  then "badge-ok"
    when "warning"  then "badge-warn"
    when "critical" then "badge-err"
    else "badge-mute"
    end
  end

  def execution_status_badge_class(status)
    case status.to_s
    when "success" then "badge-ok"
    when "failed"  then "badge-err"
    when "running" then "badge-running"
    else "badge-mute"
    end
  end

  def execution_step_badge_class(status)
    case status.to_s
    when "succeeded" then "badge-healthy"
    when "failed"    then "badge-critical"
    when "running"   then "badge-running"
    else "badge-neutral"
    end
  end

  def freshness_badge_class(status)
    case status.to_s
    when "ok"      then "badge-healthy"
    when "late"    then "badge-critical"
    when "warning" then "badge-warning"
    when "error"   then "badge-critical"
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

  def nav_link_to(path, icon: nil, &block)
    active = current_page?(path) || (path.is_a?(String) && request.path.start_with?(path))
    classes = "sidebar-link"
    classes += " active" if active

    icon_svgs = {
      "grid" => '<rect x="1" y="1" width="6" height="6" stroke="currentColor" stroke-width="1.5"/><rect x="9" y="1" width="6" height="6" stroke="currentColor" stroke-width="1.5"/><rect x="1" y="9" width="6" height="6" stroke="currentColor" stroke-width="1.5"/><rect x="9" y="9" width="6" height="6" stroke="currentColor" stroke-width="1.5"/>',
      "activity" => '<circle cx="8" cy="8" r="6" stroke="currentColor" stroke-width="1.5"/><path d="M8 4v4l3 2" stroke="currentColor" stroke-width="1.5"/>',
      "database" => '<ellipse cx="8" cy="3.5" rx="6" ry="2" stroke="currentColor" stroke-width="1.5"/><path d="M2 3.5v9c0 1.1 2.7 2 6 2s6-.9 6-2v-9" stroke="currentColor" stroke-width="1.5"/><path d="M2 8.5c0 1.1 2.7 2 6 2s6-.9 6-2" stroke="currentColor" stroke-width="1.5"/>',
      "catalog" => '<path d="M2 3h12M2 3v10h12V3" stroke="currentColor" stroke-width="1.5"/><path d="M5 7h6M5 10h4" stroke="currentColor" stroke-width="1.5"/>',
      "clock" => '<circle cx="8" cy="8" r="6" stroke="currentColor" stroke-width="1.5"/><path d="M8 4v4l3 2" stroke="currentColor" stroke-width="1.5"/>',
      "preset" => '<circle cx="8" cy="8" r="2.5" stroke="currentColor" stroke-width="1.5"/><path d="M8 1v2M8 13v2M1 8h2M13 8h2" stroke="currentColor" stroke-width="1.5"/>',
      "list" => '<path d="M2 3h12M2 8h12M2 13h8" stroke="currentColor" stroke-width="1.5"/>',
    }

    link_to(path, class: classes) do
      out = "".html_safe
      if icon && icon_svgs[icon]
        out << content_tag(:span, class: "icon") do
          content_tag(:svg, width: 14, height: 14, viewBox: "0 0 16 16", fill: "none") do
            icon_svgs[icon].html_safe
          end
        end
      end
      out << capture(&block) if block_given?
      out
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

  def freshness_delay_label(seconds)
    return nil if seconds.nil?

    days = seconds.to_i / 86_400
    return "#{days}d" if days >= 1

    duration_label(seconds)
  end

  # [label, badge_class] for the freshness column, or nil.
  def freshness_label(table)
    sla = table.table_freshness_sla
    return [ t("tables.index.fresh_no_sla"), "badge-neutral" ] if sla.nil? || !sla.enabled

    delay = freshness_delay_label(table.latest_freshness_check&.delay_seconds)
    case sla.status
    when "ok"      then [ delay || "ok", "badge-healthy" ]
    when "warning" then [ delay || "warning", "badge-warning" ]
    when "late"    then [ t("tables.index.fresh_late", delay: delay || "?"), "badge-critical" ]
    when "error"   then [ t("tables.index.fresh_error"), "badge-critical" ]
    when "no_data" then [ t("tables.index.fresh_no_data"), "badge-neutral" ]
    else [ "—", "badge-neutral" ]
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
