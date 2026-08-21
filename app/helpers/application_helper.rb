# View helpers shared across the application, covering theme selection,
# permission checks, badge classes, navigation, and formatting.
module ApplicationHelper
  include Pagy::Frontend
  # Selected theme for the <html data-theme> attribute. Dark is the default;
  # the theme toggle (CR-69) persists it on the account. The cookie is kept as
  # a fallback for the anonymous/auth screens, where there is no signed-in user.
  # @return [String] "light" or "dark".
  def html_theme
    return @theme if @theme.in?(%w[light dark])

    %w[light dark].include?(cookies[:theme]) ? cookies[:theme] : "dark"
  end

  # Operators may trigger maintenance runs; everything else that mutates a
  # plan stays admin-only.
  # @return [Boolean] true when the current user is an admin or an operator.
  def can_run_maintenance?
    current_user&.admin? || current_user&.operator?
  end

  # Whether the current user may cancel queries and queued executions.
  # @return [Boolean] true for admins and operators.
  def can_cancel_query?
    respond_to?(:current_user) && current_user && (current_user.admin? || current_user.operator?)
  end

  # Maps a Trino query state to its badge CSS class.
  # @param state [String, nil] the Trino query state.
  # @return [String] the badge class for the state.
  def query_state_badge_class(state)
    case state.to_s
    when "RUNNING" then "badge-running"
    when "QUEUED"  then "badge-warn"
    when "FINISHED", "FINISHING" then "badge-ok"
    when "FAILED"  then "badge-err"
    else "badge-mute"
    end
  end

  # Maps a user account status to its badge CSS class.
  # @param status [String, Symbol] the user status.
  # @return [String] the badge class for the status.
  def user_status_badge_class(status)
    case status.to_s
    when "active"    then "badge-ok"
    when "invited"   then "badge-warn"
    when "suspended" then "badge-err"
    else "badge-mute"
    end
  end

  # Maps a table health status to its badge CSS class.
  # @param status [String, Symbol] the health status.
  # @return [String] the badge class for the status.
  def health_badge_class(status)
    case status.to_s
    when "healthy"  then "badge-ok"
    when "warning"  then "badge-warn"
    when "critical" then "badge-err"
    else "badge-mute"
    end
  end

  # Maps an execution status to its badge CSS class.
  # @param status [String, Symbol] the execution status.
  # @return [String] the badge class for the status.
  def execution_status_badge_class(status)
    case status.to_s
    when "success" then "badge-ok"
    when "failed"  then "badge-err"
    when "running" then "badge-running"
    when "skipped" then "badge-warning"
    else "badge-pending"
    end
  end

  # Maps an execution step status to its badge CSS class.
  # @param status [String, Symbol] the step status.
  # @return [String] the badge class for the status.
  def execution_step_badge_class(status)
    case status.to_s
    when "succeeded" then "badge-ok"
    when "failed"    then "badge-err"
    when "running"   then "badge-running"
    when "skipped"   then "badge-warning"
    else "badge-pending"
    end
  end

  # Maps a freshness status to its badge CSS class.
  # @param status [String, Symbol] the freshness status.
  # @return [String] the badge class for the status.
  def freshness_badge_class(status)
    case status.to_s
    when "ok"      then "badge-ok"
    when "late"    then "badge-err"
    when "warning" then "badge-warn"
    when "error"   then "badge-err"
    else "badge-mute"
    end
  end

  # Maps a health status to the fill colour class used on the health strata bars.
  # @param status [String, Symbol] the health status.
  # @return [String] the strata fill class for the status.
  def strata_fill_class(status)
    case status.to_s
    when "healthy"  then "strata-fill-ok"
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

  # Returns the human label for an execution step, falling back to the raw
  # step name when it has no mapping.
  # @param step [String, Symbol] the step identifier.
  # @return [String] the human-readable step label.
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

  # Compares a nav target against the current path. "/" matches only the root
  # (otherwise every page would look selected); other paths match by prefix so
  # nested actions stay highlighted on their section.
  # @param path [String] the nav target to compare against the request path.
  # @return [Boolean] true when the current path matches the target.
  def active_path?(path)
    current = request.path
    return current == path || current == "#{path}/" if path == "/"

    current == path || current.start_with?(path.end_with?("/") ? path : "#{path}/")
  end

  # 1234 -> "1k", 1234_500 -> "1.2k", 10_000 -> "10k". Used for the sidebar
  # counters so big lakes stay readable.
  # @param number [Numeric] the number to compact.
  # @return [String] the compacted, human-readable number.
  def compact_number(number)
    n = number.to_i
    case n
    when 0...1_000      then n.to_s
    when 1_000...10_000 then format("%.1fk", n / 1000.0).sub(".0k", "k")
    else                     format("%.0fk", n / 1000.0)
    end
  end

  # Pager for list screens. Builds page URLs from the current query string so
  # filters survive paging, and renders pages as badges: active = badge-ok,
  # links = badge-mute, gaps as an ellipsis, disabled prev/next dimmed.
  # @param pagy [Pagy] the pagination object.
  # @return [ActiveSupport::SafeBuffer, nil] the rendered nav, nil when a
  #   single page.
  def pager_nav(pagy)
    return if pagy.pages <= 1

    content_tag(:nav, class: "pager flex items-center justify-center gap-1 my-4",
                     aria: { label: t("filters.pager") }) do
      safe_join([
        pager_arrow(pagy_page_path(pagy.prev), "&lsaquo;", enabled: pagy.prev.present?),
        safe_join(pagy.series.map do |item|
          case item
          when Integer
            if item == pagy.label.to_i
              content_tag(:span, item, class: "badge badge-ok pager-page", "aria-current": "page")
            else
              link_to(item.to_s, pagy_page_path(item), class: "badge badge-mute pager-page")
            end
          when :gap then content_tag(:span, "…", class: "pager-gap")
          end
        end),
        pager_arrow(pagy_page_path(pagy.next), "&rsaquo;", enabled: pagy.next.present?)
      ])
    end
  end

  # Path to one pager page preserving every current query param.
  def pagy_page_path(page)
    url_for(request.query_parameters.merge(page: page))
  end

  # Prev/next arrow; renders an inert dimmed span when disabled.
  def pager_arrow(path, glyph, enabled:)
    if enabled
      link_to(glyph.html_safe, path, class: "badge badge-mute pager-page", rel: "prev-next")
    else
      content_tag(:span, glyph.html_safe, class: "badge badge-mute pager-page pager-disabled")
    end
  end

  # Renders a sidebar navigation link with an optional inline SVG icon,
  # marking the link active when it matches the current page.
  # @param path [String] the destination of the link.
  # @param icon [String, nil] the icon key for the link, or nil for no icon.
  # @return [ActiveSupport::SafeBuffer] the rendered link markup.
  def nav_link_to(path, icon: nil, &block)
    active = current_page?(path) || (path.is_a?(String) && active_path?(path))
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
      "user" => '<circle cx="8" cy="6" r="3" stroke="currentColor" stroke-width="1.5"/><path d="M2.5 14c0-2.6 2.5-4.2 5.5-4.2S13.5 11.4 13.5 14" stroke="currentColor" stroke-width="1.5"/>',
      "team" => '<circle cx="5.5" cy="6" r="2.6" stroke="currentColor" stroke-width="1.5"/><circle cx="11" cy="6.5" r="2.2" stroke="currentColor" stroke-width="1.5"/><path d="M1.5 14c0-2.4 1.8-3.9 4-3.9s4 1.5 4 3.9" stroke="currentColor" stroke-width="1.5"/><path d="M10 10.4c2 .2 3.5 1.6 3.5 3.6" stroke="currentColor" stroke-width="1.5"/>',
      "bell" => '<path d="M8 1.5a4.5 4.5 0 0 0-4.5 4.5v3l-1 2h11l-1-2V6A4.5 4.5 0 0 0 8 1.5Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M6.5 12.5a1.6 1.6 0 0 0 3 0" stroke="currentColor" stroke-width="1.5"/>',
      "settings" => '<circle cx="8" cy="8" r="2.5" stroke="currentColor" stroke-width="1.5"/><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>'
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

  # Formats a duration in seconds as a short human label (e.g. "45s", "12 min",
  # "1.5 h"). Returns nil when given nil.
  # @param seconds [Numeric, nil] the duration in seconds.
  # @return [String, nil] the formatted duration, or nil when seconds is nil.
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

  # Formats a freshness delay as a day count when it spans at least a day,
  # otherwise defers to duration_label. Returns nil when given nil.
  # @param seconds [Numeric, nil] the delay in seconds.
  # @return [String, nil] the formatted delay, or nil when seconds is nil.
  def freshness_delay_label(seconds)
    return nil if seconds.nil?

    days = seconds.to_i / 86_400
    return "#{days}d" if days >= 1

    duration_label(seconds)
  end

  # [label, badge_class] for the freshness column, or nil.
  # @param table [IcebergTable] the table whose freshness is shown.
  # @return [Array, nil] the label and badge class, or nil when no SLA applies.
  def freshness_label(table)
    sla = table.table_freshness_sla
    return [ t("tables.index.fresh_no_sla"), "badge-mute" ] if sla.nil? || !sla.enabled

    delay = freshness_delay_label(table.latest_freshness_check&.delay_seconds)
    case sla.status
    when "ok"      then [ delay || "ok", "badge-ok" ]
    when "warning" then [ delay || "warning", "badge-warn" ]
    when "late"    then [ t("tables.index.fresh_late", delay: delay || "?"), "badge-err" ]
    when "error"   then [ t("tables.index.fresh_error"), "badge-err" ]
    when "no_data" then [ t("tables.index.fresh_no_data"), "badge-mute" ]
    else [ "—", "badge-mute" ]
    end
  end

  # Renders a timestamp as a muted placeholder when blank, otherwise as a
  # formatted cell with an ISO-8601 title tooltip.
  # @param value [Time, DateTime, String, nil] the timestamp to display.
  # @return [ActiveSupport::SafeBuffer] the rendered timestamp markup.
  def timestamp(value)
    return content_tag(:span, "—", class: "cell-muted") if value.blank?

    content_tag(:span, value.to_fs(:db), class: "cell-num", title: value.iso8601)
  end

  # The engine state of a lifecycle event, from its structured context when
  # present, otherwise parsed from the legacy "engine <state> (generation N)"
  # message.
  # @param event [ErrorEvent] the lifecycle event.
  # @return [String] the state label.
  def engine_event_label(event)
    state = event.context["state"]
    return state if state.presence

    event.message.to_s.sub(/\Aengine /, "").split(" (", 2).first.presence || event.context["generation"] || "—"
  end

  # The generation of a lifecycle event, from context or parsed from the legacy
  # message.
  # @param event [ErrorEvent] the lifecycle event.
  # @return [String, nil] the generation, or nil when unknown.
  def engine_event_generation(event)
    gen = event.context["generation"]
    return gen if gen.presence

    event.message.to_s[/generation (\d+)/, 1]
  end

  # Badge class for a given engine status, so each lifecycle state gets its own
  # colour in the engine strip and history table.
  # @param status [String, nil] the engine status.
  # @return [String] a badge-* CSS class.
  def engine_status_badge_class(status)
    case status
    when "up"       then "badge-healthy"
    when "starting" then "badge-warning"
    when "draining" then "badge-running"
    when "stopping" then "badge-warn"
    when "failed"   then "badge-critical"
    else                 "badge-neutral"
    end
  end

  # Human label for the current engine status, with its time/re-attempt context.
  # @param state [TrinoEngineState] the current engine state.
  # @return [String] the translated label.
  def engine_status_label(state)
    case state.status
    when "up"       then t("activity.engine.up", time: time_ago_in_words(state.status_changed_at))
    when "starting" then t("activity.engine.starting", attempt: [ state.start_attempts, 1 ].max, max: TrinoEngineSupervisor::MAX_START_ATTEMPTS)
    when "draining" then t("activity.engine.draining", time: distance_of_time_in_words_to_now(state.drain_started_at + TrinoEngineSupervisor::DRAIN_GRACE))
    when "failed"   then t("activity.engine.failed")
    else                 t("activity.engine.down")
    end
  end

  # Concise composition summary for the health tooltip in the tables list.
  # @param table [IcebergTable] the table whose composition is summarised.
  # @return [String] the tooltip text, or a "no data" translation when empty.
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
