class ProfilesController < ApplicationController
  def show
  end

  # Account preferences: display name, locale and theme. Password changes go
  # through #password so they can require the current password.
  def update
    return redirect_to(profile_path, notice: "Account updated.") if current_user.update(profile_params)

    render :show, status: :unprocessable_entity
  end

  # Password change is only exposed to local (non-SSO) accounts.
  def password
    return render(:show, status: :not_found) if current_user.sso?

    if current_user.update_with_password(password_params)
      bypass_sign_in(current_user)
      redirect_to profile_path, notice: "Password updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  # Role and status are never editable from the profile: promotions happen on
  # the users screen only.
  def profile_params
    params.require(:profile).permit(:display_name, :locale, :theme)
  end

  def password_params
    params.require(:profile).permit(:current_password, :password, :password_confirmation)
  end
end
