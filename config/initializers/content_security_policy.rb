# Be sure to restart your server when you modify this file.

# Application-wide Content-Security-Policy. See
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# Starts in report-only mode: violations are sent to the browser console (and
# to report_uri, once one exists) without blocking anything. Confirm a normal
# session - Turbo navigation, Turbo Streams over the solid_cable websocket,
# the importmap-loaded JS, Tailwind-built CSS - produces no violations, then
# flip content_security_policy_report_only to false in a follow-up change.
#
# style-src allows 'unsafe-inline': a handful of views (progress bars, health
# bars) set inline `style="width: ...%"` for a value computed per request.
# Nonces only cover <script>/<style> blocks, not the style="" attribute, so
# closing this needs rewriting those five views to set width via a data
# attribute and a Stimulus controller instead - left as follow-up rather than
# bundled with turning the header on.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.connect_src :self
    policy.base_uri    :self
    policy.frame_ancestors :none
  end

  # Nonces let importmap-rails and Turbo tag their own inline <script> blocks
  # as trusted without needing 'unsafe-inline' on script-src.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]

  config.content_security_policy_report_only = true
end
