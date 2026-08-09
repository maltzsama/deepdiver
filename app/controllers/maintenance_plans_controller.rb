class MaintenancePlansController < ApplicationController
  before_action :require_admin!, only: %i[run pause resume]
  before_action :set_plan, only: %i[show run pause resume]

  def index
    @plans = MaintenancePlan.includes(:iceberg_table, :maintenance_policy).order(:id)
  end

  def show; end

  def run
    MaintenanceOrchestrator.run_plan(@plan.id)
    redirect_to @plan, notice: "Maintenance enqueued."
  end

  def pause
    @plan.update!(is_paused: true)
    redirect_to @plan, notice: "Plan paused."
  end

  def resume
    @plan.update!(is_paused: false)
    redirect_to @plan, notice: "Plan resumed."
  end

  private

  def set_plan
    @plan = MaintenancePlan.find(params[:id])
  end
end
