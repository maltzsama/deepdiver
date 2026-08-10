class MaintenanceSchedulesController < ApplicationController
  before_action :set_schedule, only: %i[show edit update destroy]

  def index
    authorize MaintenanceSchedule
    @schedules = MaintenanceSchedule.includes(iceberg_table: :catalog).order(:iceberg_table_id)
  end

  def show
    authorize @schedule
    @executions = @schedule.execution_histories.latest.limit(20)
  end

  def new
    authorize MaintenanceSchedule
    @schedule = MaintenanceSchedule.new
    @schedule.iceberg_table_id = params[:iceberg_table_id] if params[:iceberg_table_id]
  end

  def create
    authorize MaintenanceSchedule
    @schedule = MaintenanceSchedule.new(schedule_params)

    if @schedule.save
      redirect_to @schedule.iceberg_table, notice: "Schedule created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @schedule
  end

  def update
    authorize @schedule
    if @schedule.update(schedule_params)
      redirect_to @schedule, notice: "Schedule updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @schedule
    @table = @schedule.iceberg_table
    @schedule.destroy
    redirect_to @table, notice: "Schedule deleted."
  end

  private

  def set_schedule
    @schedule = MaintenanceSchedule.find(params[:id])
  end

  private

  def schedule_params
    params.require(:maintenance_schedule)
          .permit(:iceberg_table_id, :operation, :cron, :is_paused, config: {})
  end
end
