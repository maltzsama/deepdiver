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

  # Whether SSO (OIDC) sign-in is enabled, read from SSO_ENABLED.
  # @return [Boolean] true when SSO is enabled
  def sso_enabled?
    ENV.fetch("SSO_ENABLED", "true") == "true"
  end

  # Whether the local email/password login is available. Always enabled when
  # SSO is off; otherwise read from LOCAL_LOGIN_ENABLED.
  # @return [Boolean] true when the local login form should show
  def local_login_enabled?
    return true unless sso_enabled?

    ENV.fetch("LOCAL_LOGIN_ENABLED", "true") == "true"
  end

  # Label shown for the SSO button on the sign-in screen, from
  # OIDC_PROVIDER_LABEL.
  # @return [String] the provider display label
  def provider_label
    ENV.fetch("OIDC_PROVIDER_LABEL", "SSO")
  end
end
