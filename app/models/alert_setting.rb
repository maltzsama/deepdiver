# Global alert transport configuration: the SMTP server (username/password,
# sender) used for Email channels and the single Slack webhook URL. Editing it
# in the admin panel updates how every channel delivers.
class AlertSetting < ApplicationRecord
  # Returns the singleton settings row, creating it on first access.
  #
  # @return [AlertSetting] the global settings record
  def self.instance
    first_or_create!
  end

  # The Slack webhook URL, or nil when not configured.
  #
  # @return [String, nil]
  def slack_webhook
    slack_webhook_url.presence
  end

  # The SMTP settings hash for Action Mailer, or nil when SMTP is not configured.
  #
  # @return [Hash, nil] the smtp_settings for ActionMailer
  def smtp_settings
    return nil if smtp_address.blank?

    {
      address: smtp_address,
      port: smtp_port || 587,
      user_name: smtp_user_name.presence,
      password: smtp_password.presence,
      authentication: smtp_user_name.present? ? :plain : nil
    }.compact
  end

  # The sender address for outgoing alerts, defaulting to the dev placeholder.
  #
  # @return [String]
  def from_address
    smtp_from.presence || "alerts@deepdiver.local"
  end
end
