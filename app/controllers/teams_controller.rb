# Manages teams: named groups of users that own sets of catalogs. Provides the
# standard CRUD; each action authorizes with Pundit.
class TeamsController < ApplicationController
  before_action :set_team, only: %i[show edit update destroy]

  # Lists all teams with their members, ordered by name.
  def index
    authorize Team
    @teams = Team.includes(:members).order(:name)
  end

  # Shows a single team.
  def show
    authorize @team
  end

  # Renders the form for creating a team.
  def new
    authorize Team
    @team = Team.new
  end

  # Creates a team and redirects to the teams index, or re-renders the form.
  def create
    authorize Team
    @team = Team.new(team_params)
    if @team.save
      redirect_to teams_path, notice: t("teams.notices.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Renders the edit form for a team.
  def edit
    authorize @team
  end

  # Updates the team and redirects to it, or re-renders the form on failure.
  def update
    authorize @team
    if @team.update(team_params)
      redirect_to @team, notice: t("teams.notices.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Destroys the team and redirects to the teams index.
  def destroy
    authorize @team
    @team.destroy
    redirect_to teams_path, notice: t("teams.notices.destroyed")
  end

  private

  # Loads the team for the current request.
  def set_team
    @team = Team.find(params[:id])
  end

  # Strong parameters for a team, including its catalogs and member user ids.
  def team_params
    params.require(:team).permit(:name, :description, catalog_ids: [], user_ids: [])
  end
end
