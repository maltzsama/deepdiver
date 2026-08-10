class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  layout :layout_by_resource

  # Devise screens use the auth layout (no header/navigation).
  def layout_by_resource
    devise_controller? ? "auth" : "application"
  end

  # Pundit: after a failed authorization, redirect with an alert.
  def user_not_authorized(exception)
    flash[:alert] = "You do not have permission to perform that action"
    redirect_back(fallback_location: root_path)
  end
end
