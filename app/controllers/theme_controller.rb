class ThemeController < ApplicationController
  THEMES = %w[light dark].freeze

  # Switches the paper/ink theme and persists it in a cookie. The topbar
  # button posts here; the layout reads the cookie as `data-theme`.
  def toggle
    theme = if params[:theme].in?(THEMES)
              params[:theme]
    else
              cookies[:theme] == "light" ? "dark" : "light"
    end

    cookies[:theme] = { value: theme, expires: 1.year.from_now, same_site: :lax }
    redirect_back fallback_location: root_path
  end
end
