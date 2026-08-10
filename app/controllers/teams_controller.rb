class TeamsController < ApplicationController
  before_action :set_team, only: %i[show edit update destroy]

  def index
    authorize Team
    @teams = Team.includes(:members).order(:name)
  end

  def show
    authorize @team
  end

  def new
    authorize Team
    @team = Team.new
  end

  def create
    authorize Team
    @team = Team.new(team_params)
    if @team.save
      redirect_to teams_path, notice: t("teams.notices.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @team
  end

  def update
    authorize @team
    if @team.update(team_params)
      redirect_to @team, notice: t("teams.notices.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @team
    @team.destroy
    redirect_to teams_path, notice: t("teams.notices.destroyed")
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name, :description, catalog_ids: [], user_ids: [])
  end
end
