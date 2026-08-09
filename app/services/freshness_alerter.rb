# Alerts with hysteresis: alert on entering late, on recovery, and only
# reinforce when the delay doubles the budget. Otherwise a table stopped for a
# day would mention the channel every hour and train everyone to mute it.
class FreshnessAlerter
  ESCALATION_FACTOR = 2

  def initialize(sla, result)
    @sla = sla
    @result = result
  end

  def call
    previous = @sla.status
    current = map_status(@result.status)
    changed = current != previous

    @sla.update!(
      status: current,
      status_changed_at: changed ? Time.current : @sla.status_changed_at,
      breached_since: current == "late" ? (@sla.breached_since || Time.current) : nil
    )

    notify!(current, previous) if should_notify?(current, previous)
  end

  private

  def map_status(status)
    TableFreshnessSla::STATUSES.include?(status.to_s) ? status.to_s : "unknown"
  end

  def should_notify?(current, previous)
    return true if current == "late" && previous != "late"
    return true if current == "ok" && previous == "late"
    return true if current == "late" && escalated?

    false
  end

  def escalated?
    budget = @sla.sla_minutes * 60
    (@result.delay_seconds || 0) > budget * ESCALATION_FACTOR
  end

  def notify!(current, previous)
    delay = @result.delay_seconds
    table = @sla.iceberg_table.fully_qualified_name
    level = if current == "late" && previous != "late" then "late"
    elsif current == "ok" then "recovered"
    else "escalated"
    end

    message = case level
    when "late"     then "Freshness: #{table} is late (#{human(delay)} behind, SLA #{@sla.sla_minutes} min)"
    when "recovered" then "Freshness: #{table} recovered"
    when "escalated" then "Freshness: #{table} delay doubled the budget (#{human(delay)})"
    end

    SlackAlert.notify(message, webhook: @sla.slack_webhook_url)

    @sla.update!(last_alert_at: Time.current, last_alert_level: level)
  end

  def human(seconds)
    return "0s" if seconds.nil?

    minutes = seconds / 60
    if minutes < 60
      "#{minutes.to_i} min"
    else
      "#{(minutes / 60.0).round(1)} h"
    end
  end
end
