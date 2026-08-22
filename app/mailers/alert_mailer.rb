# Sends alert emails to configured channel recipients.
class AlertMailer < ApplicationMailer
  # Sends an alert to one or more recipients.
  #
  # @param to [String] comma-separated recipient addresses
  # @param subject [String] the email subject
  # @param body [String] the plain-text alert body
  def alert(to:, subject:, body:)
    setting = AlertSetting.instance
    mail(
      to: to,
      subject: subject,
      from: setting.from_address,
      delivery_method_settings: alert_delivery_settings
    ) do |format|
      format.text { render plain: body }
    end
  end
end
