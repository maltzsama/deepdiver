# Base controller for the whole app: requires an authenticated user, wires
# Pundit authorization, and handles the per-user locale/theme and the layout
# choice (auth vs. application).
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Method

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :set_locale_and_theme, if: :user_signed_in?
  before_action :set_failed_execution_count, if: :user_signed_in?

  # A forgotten `authorize` is otherwise indistinguishable from an intentional
  # one: the action just runs for any signed-in user. This turns the omission
  # into a loud failure. Controllers that act only on current_user opt out
  # explicitly with skip_after_action, which documents the decision.
  # Not verify_policy_scoped: index actions here authorize the class
  # (`authorize IcebergTable`) rather than scoping a relation, so
  # verify_authorized is the check that matches how this app is written.
  after_action :verify_authorized, unless: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  layout :layout_by_resource

  # Language and theme are account preferences (CR-69), read from the profile
  # instead of the old cookie. Auth screens keep the dark paper look.
  def set_locale_and_theme
    I18n.locale = current_user.locale if current_user.locale.in?(I18n.available_locales.map(&:to_s))
    @theme = current_user.theme
  end

  # Devise screens use the auth layout (no header/navigation).
  def layout_by_resource
    devise_controller? ? "auth" : "application"
  end

  # Pundit: after a failed authorization, redirect with an alert.
  def user_not_authorized(exception)
    flash[:alert] = t("shared.unauthorized")
    redirect_back(fallback_location: root_path)
  end

  private

  def set_failed_execution_count
    return unless request.get? || request.head?

    @failed_execution_count = Rails.cache.fetch("failed_execution_count", expires_in: 30.seconds) do
      ExecutionHistory.where(status: "failed").count
    end
  end
end
