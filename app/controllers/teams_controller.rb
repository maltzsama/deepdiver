# Team administration: named groups of users that error events can be
# assigned to. Full CRUD is admin-only.
class TeamsController < ApplicationController
  before_action :set_team, only: %i[show edit update destroy]

  # Lists every team with its member count.
  def index
    authorize Team
    @teams = Team.order(:name)
  end

  # Shows one team and its members.
  def show
    authorize @team
  end

  def new
    @team = Team.new
    authorize @team
  end

  def create
    @team = Team.new(team_params)
    authorize @team
    if @team.save
      redirect_to team_path(@team), notice: t("teams.notices.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @team
  end

  def update
    authorize @team
    if @team.update(team_params)
      redirect_to team_path(@team), notice: t("teams.notices.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @team
    @team.destroy!
    redirect_to teams_path, notice: t("teams.notices.destroyed")
  end

  private

  # Finds the team for member actions.
  def set_team
    @team = Team.find(params[:id])
  end

  # Only admins reach these actions; membership is a plain id list.
  def team_params
    params.require(:team).permit(:name, :description, member_ids: [])
  end
end
