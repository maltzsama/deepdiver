# Sends an alert to a specific destination: a Slack #channel and/or email
# recipients, using the global transport (Slack webhook + SMTP) from
# AlertSetting. The freshness alerter passes the SLA's own destination so each
# table's alerts go exactly where they are configured to go.
class AlertNotifier
  # Sends an alert to the given destinations.
  #
  # @param subject [String] the alert subject (short, e.g. "Freshness late")
  # @param message [String] the alert message (rich in context)
  # @param severity [String] the alert severity (warning/severe/critical)
  # @param slack_channel [String, nil] a Slack #channel to post to
  # @param email_to [String, nil] comma-separated email recipients
  # @param context [Hash] extra keys for message templates
  # @return [String, nil] an error message when every transport failed
  def self.notify(subject:, message:, severity:, slack_channel: nil, email_to: nil, context: {})
    new(subject:, message:, severity:, slack_channel:, email_to:, context:).call
  end

  # Creates the notifier for an alert.
  #
  # @param subject [String] the alert subject
  # @param message [String] the alert message
  # @param severity [String] the alert severity
  # @param slack_channel [String, nil] a Slack #channel to post to
  # @param email_to [String, nil] comma-separated email recipients
  # @param context [Hash] extra keys for message templates
  def initialize(subject:, message:, severity:, slack_channel: nil, email_to: nil, context: {})
    @subject = subject
    @message = message
    @severity = severity.to_s
    @slack_channel = slack_channel
    @email_to = email_to
    @context = context
  end

  # Delivers over Slack and/or Email and returns the first error, if any.
  #
  # @return [String, nil] an error message when a transport failed
  def call
    errors = []
    errors << send_slack if @slack_channel.present?
    errors << send_email if @email_to.present?

    errors.compact.first
  end

  private

  # Posts the message to the destination's Slack #channel.
  #
  # @return [String, nil] an error message when the transport failed
  def send_slack
    webhook = AlertSetting.instance.slack_webhook
    unless webhook
      return "no Slack webhook configured (Alert Settings)"
    end

    SlackAlert.notify(@message, webhook: webhook, channel: @slack_channel)
    nil
  rescue StandardError => e
    e.message
  end

  # Emails the message to the destination's recipients.
  #
  # @return [String, nil] an error message when the transport failed
  def send_email
    recipients = @email_to.split(",").map(&:strip).reject(&:blank?)
    return "no email recipients configured" if recipients.empty?

    AlertMailer.alert(to: recipients.join(","), subject: @subject, body: @message).deliver_now
    nil
  rescue StandardError => e
    e.message
  end
end
