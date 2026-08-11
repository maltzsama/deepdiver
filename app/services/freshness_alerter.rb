# Alerts with hysteresis: alert on entering late, on recovery, and only
# reinforce when the delay doubles the budget. Otherwise a table stopped for a
# day would mention the channel every hour and train everyone to mute it.
class FreshnessAlerter
  ESCALATION_FACTOR = 2

  # Creates the alerter for a freshness SLA and its latest probe result.
  #
  # @param sla [TableFreshnessSla] the SLA to update
  # @param result [FreshnessProbe::Result] the latest probe result
  def initialize(sla, result)
    @sla = sla
    @result = result
  end

  # Applies the probe result to the SLA with hysteresis and alerts as needed.
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

  # Maps a probe status into a valid SLA status, defaulting unknown values.
  #
  # @param status [Object] the raw probe status
  # @return [String] a TableFreshnessSla status
  def map_status(status)
    TableFreshnessSla::STATUSES.include?(status.to_s) ? status.to_s : "unknown"
  end

  # Whether the transition warrants an alert (late entry, recovery, or escalation).
  #
  # @param current [String] the new SLA status
  # @param previous [String] the previous SLA status
  # @return [Boolean] true when an alert should be sent
  def should_notify?(current, previous)
    return true if current == "late" && previous != "late"
    return true if current == "ok" && previous == "late"
    return true if current == "late" && escalated?

    false
  end

  # Whether the delay has doubled the SLA budget.
  #
  # @return [Boolean] true when the delay exceeds twice the budget
  def escalated?
    budget = @sla.sla_minutes * 60
    (@result.delay_seconds || 0) > budget * ESCALATION_FACTOR
  end

  # Sends the alert message and stamps last_alert_at/level on the SLA.
  #
  # @param current [String] the new SLA status
  # @param previous [String] the previous SLA status
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

  # Formats a delay in seconds as a compact human-readable string.
  #
  # @param seconds [Integer, nil] the delay in seconds
  # @return [String] e.g. "45 min" or "2.5 h"
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
