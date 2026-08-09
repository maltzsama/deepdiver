# Single source of truth for how people sign in to the application.
#
# SSO_ENABLED=true          -> OIDC button on the sign-in screen
# LOCAL_LOGIN_ENABLED=true  -> the email/password form also shows up
#
# The local login exists as a break-glass: if the IdP goes down, nobody gets
# in to diagnose anything. Keeping it on with very few local accounts is a
# deliberate operational decision, not an oversight.
module AuthConfig
  module_function

  def sso_enabled?
    ENV.fetch("SSO_ENABLED", "true") == "true"
  end

  def local_login_enabled?
    return true unless sso_enabled?

    ENV.fetch("LOCAL_LOGIN_ENABLED", "true") == "true"
  end

  def provider_label
    ENV.fetch("OIDC_PROVIDER_LABEL", "SSO")
  end
end
