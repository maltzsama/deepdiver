class ThemeController < ApplicationController
  THEMES = %w[light dark].freeze

  # Switches the paper/ink theme. It used to live in a cookie and disappear
  # when the person changed machines; since CR-69 the theme is an account
  # preference. The cookie stays as a fast path for the current request.
  def toggle
    theme = if params[:theme].in?(THEMES)
              params[:theme]
    else
              current_user.theme == "light" ? "dark" : "light"
    end

    current_user.update!(theme: theme)
    cookies[:theme] = { value: theme, expires: 1.year.from_now, same_site: :lax }
    redirect_back fallback_location: root_path
  end
end
