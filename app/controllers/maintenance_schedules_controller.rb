class MaintenanceSchedulesController < ApplicationController
  before_action :require_admin!, except: %i[index show]

  def index
    @schedules = MaintenanceSchedule.includes(iceberg_table: :catalog).order(:iceberg_table_id)
  end

  def show
    @schedule = MaintenanceSchedule.find(params[:id])
    @executions = @schedule.execution_histories.latest.limit(20)
  end

  def new
    @schedule = MaintenanceSchedule.new
    @schedule.iceberg_table_id = params[:iceberg_table_id] if params[:iceberg_table_id]
  end

  def create
    @schedule = MaintenanceSchedule.new(schedule_params)

    if @schedule.save
      redirect_to @schedule.iceberg_table, notice: "Schedule created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @schedule = MaintenanceSchedule.find(params[:id])
  end

  def update
    @schedule = MaintenanceSchedule.find(params[:id])

    if @schedule.update(schedule_params)
      redirect_to @schedule, notice: "Schedule updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @schedule = MaintenanceSchedule.find(params[:id])
    @table = @schedule.iceberg_table
    @schedule.destroy
    redirect_to @table, notice: "Schedule deleted."
  end

  private

  def schedule_params
    params.require(:maintenance_schedule)
          .permit(:iceberg_table_id, :operation, :cron, :is_paused, config: {})
  end
end
