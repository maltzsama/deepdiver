class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!

  private

  def require_admin!
    return if current_user.admin?

    flash[:alert] = "You do not have permission to perform that action"
    redirect_back(fallback_location: root_path)
  end
end
