# Manages the singleton global alert settings: SMTP server and the Slack
# webhook URL used by every channel. Each action authorizes with Pundit.
class AlertSettingsController < ApplicationController
  # Shows the global settings form.
  def show
    authorize AlertSetting
    @setting = AlertSetting.instance
  end

  # Updates the global settings and redirects to the form, or re-renders it.
  def update
    authorize AlertSetting
    @setting = AlertSetting.instance
    if @setting.update(setting_params)
      redirect_to alert_settings_path, notice: t("alert_settings.notices.updated")
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  # Strong parameters for the global alert settings.
  def setting_params
    params.require(:alert_setting).permit(:smtp_address, :smtp_port, :smtp_user_name,
                                          :smtp_password, :smtp_from, :slack_webhook_url)
  end
end
