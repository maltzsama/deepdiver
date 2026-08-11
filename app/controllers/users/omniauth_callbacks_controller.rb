module Users
  # Handles the OpenID Connect sign-in callback from Devise. Finds or rejects
  # the user from the omniauth payload and records SSO failures as error events.
  # The openid_connect route skips CSRF verification because the IdP posts to it.
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :verify_authenticity_token, only: :openid_connect

    # Completes SSO sign-in for a known user, or rejects unknown identities
    # with an alert.
    def openid_connect
      user = User.from_omniauth(request.env["omniauth.auth"])

      if user&.persisted?
        sign_in_and_redirect user, event: :authentication
        set_flash_message!(:notice, :success, kind: AuthConfig.provider_label)
      else
        record_sso_failure("identity-not-found")
        redirect_to new_user_session_path,
                    alert: t("auth.errors.sso_failed")
      end
    end

    # Records a failed omniauth flow and redirects back to the sign-in screen.
    def failure
      record_sso_failure("omniauth-failure")
      redirect_to new_user_session_path,
                  alert: t("auth.errors.sso_failed")
    end

    private

    # Records an informational SSO error event; never breaks the auth flow.
    def record_sso_failure(kind)
      ErrorEvent.record(catalog: nil, schema: "sso", operation: "sso",
                        source_system: "sso", error_class: kind.to_s,
                        message: "SSO sign-in failed (#{kind})")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      # The event is informational; auth flow must not break because of it.
    end
  end
end
