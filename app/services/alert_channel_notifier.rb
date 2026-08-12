# Routes an alert to every enabled channel that meets the alert's severity,
# honoring each channel's cooldown and message template. Slack goes to the
# global webhook with the channel's #channel, Email goes to the channel's
# recipients through AlertMailer.
class AlertChannelNotifier
  # Sends an alert to all eligible channels.
  #
  # @param subject [String] the alert subject (short, e.g. "Freshness late")
  # @param message [String] the default alert message (rich in context)
  # @param severity [String] the alert severity (warning/severe/critical)
  # @param context [Hash] extra keys available to message templates (e.g. table)
  def self.notify(subject:, message:, severity:, context: {})
    new(subject:, message:, severity:, context:).call
  end

  # Creates the notifier for an alert.
  #
  # @param subject [String] the alert subject
  # @param message [String] the default alert message
  # @param severity [String] the alert severity
  # @param context [Hash] extra template variables
  def initialize(subject:, message:, severity:, context: {})
    @subject = subject
    @message = message
    @severity = severity.to_s
    @context = context
  end

  # Iterates over enabled channels and sends the alert to the eligible ones.
  #
  # @return [Array<AlertChannel>] the channels the alert was sent to
  def call
    sent_to = []
    AlertChannel.enabled.find_each do |channel|
      next unless channel.receives?(@severity)
      next if channel.cooling_down?

      deliver(channel)
      sent_to << channel
    end
    sent_to
  end

  # Sends the alert to one specific channel, bypassing the cooldown. Used by
  # the admin "test" action so a test reaches its destination immediately.
  #
  # @param channel [AlertChannel] the channel to deliver to
  def deliver_to!(channel)
    deliver(channel)
    channel
  end

  private

  # Renders the channel's template and delivers over Slack and/or Email.
  #
  # @param channel [AlertChannel] the channel to deliver to
  def deliver(channel)
    body = render(channel)
    errors = []
    errors << send_slack(channel, body) if channel.slack_channel.present?
    errors << send_email(channel, body) if channel.email_to.present?

    channel.update!(last_sent_at: Time.current, last_error: errors.compact.first)
  rescue StandardError => e
    channel.update!(last_error: e.message)
    Rails.logger.error("Alert channel #{channel.name} failed: #{e.message}")
  end

  # Posts the rendered message to the channel's Slack #channel.
  #
  # @param channel [AlertChannel] the channel
  # @param body [String] the rendered message
  # @return [String, nil] an error message when the transport failed
  def send_slack(channel, body)
    webhook = AlertSetting.instance.slack_webhook
    unless webhook
      return "no Slack webhook configured (Alert Settings)"
    end

    SlackAlert.notify(body, webhook: webhook, channel: channel.slack_channel)
    nil
  rescue StandardError => e
    e.message
  end

  # Emails the rendered message to the channel's recipients.
  #
  # @param channel [AlertChannel] the channel
  # @param body [String] the rendered message
  # @return [String, nil] an error message when the transport failed
  def send_email(channel, body)
    recipients = channel.email_to.split(",").map(&:strip).reject(&:blank?)
    return "no recipients configured" if recipients.empty?

    AlertMailer.alert(to: recipients.join(","), subject: @subject, body: body).deliver_now
    nil
  rescue StandardError => e
    e.message
  end

  # Renders the channel's message template with the alert's variables. Falls
  # back to the default "subject: message" shape when no template is set.
  #
  # @param channel [AlertChannel] the channel
  # @return [String] the rendered message
  def render(channel)
    template = channel.message_template.presence || "%{subject}: %{message}"
    vars = @context.transform_keys(&:to_sym).merge(subject: @subject, message: @message, severity: @severity)
    template.gsub(/%\{([^}]+)\}/) { vars.fetch($1.to_sym, "") }
  end
end
