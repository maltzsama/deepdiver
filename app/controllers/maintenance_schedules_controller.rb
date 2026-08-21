# Manages maintenance schedules: recurring maintenance operations for
# individual iceberg tables. Provides the standard CRUD; each action
# authorizes with Pundit.
class MaintenanceSchedulesController < ApplicationController
  before_action :set_schedule, only: %i[show edit update destroy]

  # Lists all schedules with their table and catalog, ordered by table.
  def index
    authorize MaintenanceSchedule
    @schedules = MaintenanceSchedule.includes(iceberg_table: :catalog).order(:iceberg_table_id)
  end

  # Shows a schedule with its most recent execution history.
  def show
    authorize @schedule
    @executions = @schedule.execution_histories.latest.limit(20)
  end

  # Renders the form for creating a schedule, pre-selecting the table when
  # one is given.
  def new
    authorize MaintenanceSchedule
    @schedule = MaintenanceSchedule.new
    @schedule.iceberg_table_id = params[:iceberg_table_id] if params[:iceberg_table_id]
  end

  # Creates a schedule and redirects to its table, or re-renders the form.
  def create
    authorize MaintenanceSchedule
    @schedule = MaintenanceSchedule.new(schedule_params)

    if @schedule.save
      redirect_to @schedule.iceberg_table, notice: t("schedules.notices.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  # Renders the edit form for a schedule.
  def edit
    authorize @schedule
  end

  # Updates the schedule and redirects to it, or re-renders the form.
  def update
    authorize @schedule
    if @schedule.update(schedule_params)
      redirect_to @schedule, notice: t("schedules.notices.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Destroys the schedule and redirects to its table.
  def destroy
    authorize @schedule
    @table = @schedule.iceberg_table
    @schedule.destroy
    redirect_to @table, notice: t("schedules.notices.destroyed")
  end

  private

  # Loads the schedule for the current request.
  def set_schedule
    @schedule = MaintenanceSchedule.find(params[:id])
  end

  private

  # Strong parameters for a schedule, including its config.
  def schedule_params
    params.require(:maintenance_schedule)
          .permit(:iceberg_table_id, :operation, :cron, :is_paused, config: {})
  end
end
