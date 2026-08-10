class UsersController < ApplicationController
  def index
    authorize User
    @users = User.includes(:invited_by).order(:email)
    @users = @users.where(status: params[:status]) if params[:status].in?(User::STATUSES)
  end

  def new
    authorize User
    @user = User.new(role: "viewer")
  end

  def create
    authorize User
    @user, error = UserInviter.call(
      email: params[:user][:email],
      role: params[:user][:role] || "viewer",
      invited_by: current_user
    )

    if error
      @user ||= User.new(email: params[:user][:email])
      @user.errors.add(:base, error)
      render :new, status: :unprocessable_entity
    else
      redirect_to users_path, notice: t("users.notices.invited", email: @user.email)
    end
  end

  def update
    @user = User.find(params[:id])
    authorize @user
    @user.change_role!(
      params[:user][:role],
      changed_by: current_user,
      reason: params[:user][:reason].presence
    )
    redirect_to users_path, notice: t("users.notices.role_updated", email: @user.email)
  end

  def suspend
    @user = User.find(params[:id])
    authorize @user, :suspend?
    @user.suspend!(by: current_user)
    redirect_to users_path, notice: t("users.notices.suspended", email: @user.email)
  end

  def reactivate
    @user = User.find(params[:id])
    authorize @user, :reactivate?
    @user.reactivate!(by: current_user)
    redirect_to users_path, notice: t("users.notices.reactivated", email: @user.email)
  end
end
