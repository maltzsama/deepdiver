# Base class for all mailers. Configures the default sender and the "mailer"
# layout used by every outgoing email.
#
# Delivery settings (SMTP server, port, credentials) are read from the
# admin-configured AlertSetting so email alerts work without touching
# environment-specific mailer configs.
class ApplicationMailer < ActionMailer::Base
  default from: "alerts@deepdiver.local"
  layout "mailer"

  private

  # ActionMailer delivery_method_settings hash built from the admin-configured
  # SMTP credentials. Returns nil when SMTP is not configured, which tells
  # deliver_now to use the Rails default (likely localhost in development).
  #
  # @return [Hash, nil]
  def alert_delivery_settings
    AlertSetting.instance.smtp_settings
  end
end
