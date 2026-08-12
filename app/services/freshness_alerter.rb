# Alerts with hysteresis and progressive severity. A table that keeps slipping
# escalates warning -> severe -> critical (each band configurable in minutes on
# the SLA), re-alerting only when the level actually rises; recovery alerts once
# when it comes back. This keeps a day-long outage from paging the channel every
# hour.
class FreshnessAlerter
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
    previous_status = @sla.status
    previous_severity = @sla.severity
    current = map_status(@result.status)
    changed = current != previous_status
    severity = severity_for(@result.delay_seconds)

    @sla.update!(
      status: current,
      severity: severity,
      status_changed_at: changed ? Time.current : @sla.status_changed_at,
      breached_since: current == "late" ? (@sla.breached_since || Time.current) : nil
    )

    notify!(current, severity, previous_status) if should_notify?(current, severity, previous_status, previous_severity)
  end

  private

  # Maps a probe status into a valid SLA status, defaulting unknown values.
  #
  # @param status [Object] the raw probe status
  # @return [String] a TableFreshnessSla status
  def map_status(status)
    TableFreshnessSla::STATUSES.include?(status.to_s) ? status.to_s : "unknown"
  end

  # Whether the transition warrants an alert: late entry, recovery, or an
  # escalation to a higher severity level.
  #
  # @param current [String] the new SLA status
  # @param severity [String, nil] the new progressive severity
  # @param previous_status [String] the previous SLA status
  # @param previous_severity [String, nil] the previous severity
  # @return [Boolean] true when an alert should be sent
  def should_notify?(current, severity, previous_status, previous_severity)
    return true if current == "late" && previous_status != "late"
    return true if current == "ok" && previous_status == "late"
    return true if severity && severity_level(severity) > severity_level(previous_severity)

    false
  end

  # Numeric rank of a severity for comparison; unknown values rank as 0.
  #
  # @param severity [String, nil] the severity to rank
  # @return [Integer] 0 for unknown, 1..3 for warning..critical
  def severity_level(severity)
    TableFreshnessSla::SEVERITY_LEVEL.fetch(severity.to_s, 0)
  end

  # Maps an absolute delay to the highest severity it triggers, using the
  # SLA's own configurable bands.
  #
  # @param delay_seconds [Integer, nil] the delay in seconds
  # @return [String, nil] "warning"/"severe"/"critical", or nil under the warning band
  def severity_for(delay_seconds)
    delay = delay_seconds.to_i
    bands = {
      "critical" => @sla.critical_after_minutes * 60,
      "severe"   => @sla.severe_after_minutes * 60,
      "warning"  => @sla.warning_after_minutes * 60
    }
    bands.each do |level, threshold|
      return level if delay >= threshold
    end
    nil
  end

  # Sends the alert to the SLA's configured destination and stamps
  # last_alert_at/level on the SLA.
  #
  # @param current [String] the new SLA status
  # @param severity [String, nil] the progressive severity
  # @param previous_status [String] the previous SLA status
  def notify!(current, severity, previous_status)
    table = @sla.iceberg_table.fully_qualified_name
    delay = @result.delay_seconds
    level = if current == "ok" then "recovered"
    elsif current == "late" && previous_status != "late" then severity.presence || "warning"
    else severity
    end

    message = case level
    when "recovered"
      "Freshness: #{table} recovered"
    when "critical"
      "Freshness: #{table} is critically late (#{human(delay)} behind, SLA #{@sla.sla_minutes} min)"
    when "severe"
      "Freshness: #{table} is severely late (#{human(delay)} behind, SLA #{@sla.sla_minutes} min)"
    else
      "Freshness: #{table} is late (#{human(delay)} behind, SLA #{@sla.sla_minutes} min)"
    end

    error = AlertNotifier.notify(
      subject: "Freshness #{level}: #{table}",
      message: message,
      severity: level == "recovered" ? "warning" : level,
      slack_channel: @sla.slack_channel,
      email_to: @sla.email_to,
      context: {
        table: table,
        delay: human(delay),
        sla: @sla.sla_minutes,
        severity: level
      }
    )
    Rails.logger.warn("Freshness alert not delivered: #{error}") if error

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
