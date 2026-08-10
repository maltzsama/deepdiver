class MaintenancePlansController < ApplicationController
  before_action :set_plan, only: %i[show run pause resume]

  def index
    authorize MaintenancePlan
    @plans = MaintenancePlan.includes(:iceberg_table, :maintenance_policy).order(:id)
  end

  def show
    authorize @plan
  end

  def run
    authorize @plan, :run?
    MaintenanceOrchestrator.run_plan(@plan.id)
    redirect_to @plan, notice: "Maintenance enqueued."
  end

  def pause
    authorize @plan, :pause?
    @plan.update!(is_paused: true)
    redirect_to @plan, notice: "Plan paused."
  end

  def resume
    authorize @plan, :resume?
    @plan.update!(is_paused: false)
    redirect_to @plan, notice: "Plan resumed."
  end

  private

  def set_plan
    @plan = MaintenancePlan.find(params[:id])
  end
end
