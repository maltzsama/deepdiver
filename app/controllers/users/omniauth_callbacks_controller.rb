module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :verify_authenticity_token, only: :openid_connect

    def openid_connect
      user = User.from_omniauth(request.env["omniauth.auth"])

      if user&.persisted?
        sign_in_and_redirect user, event: :authentication
        set_flash_message!(:notice, :success, kind: AuthConfig.provider_label)
      else
        redirect_to new_user_session_path,
                    alert: t("auth.errors.sso_failed")
      end
    end

    def failure
      redirect_to new_user_session_path,
                  alert: t("auth.errors.sso_failed")
    end
  end
end
