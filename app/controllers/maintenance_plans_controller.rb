class MaintenancePlansController < ApplicationController
  before_action :set_plan, only: %i[show edit update run pause resume]

  def index
    authorize MaintenancePlan
    @plans = MaintenancePlan.includes(:iceberg_table, :maintenance_policy).order(:id)
  end

  def show
    authorize @plan
  end

  def edit
    authorize @plan
    ensure_all_steps_present
  end

  def update
    authorize @plan
    if @plan.update(resourced_params)
      redirect_to @plan, notice: "Plan updated."
    else
      ensure_all_steps_present
      render :edit, status: :unprocessable_content
    end
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
    @plan.update!(is_paused: false, consecutive_failures: 0, needs_review: false)
    redirect_to @plan, notice: "Plan resumed."
  end

  private

  def set_plan
    @plan = MaintenancePlan.find(params[:id])
  end

  def plan_params
    params.require(:maintenance_plan).permit(
      :cron,
      maintenance_steps_attributes: [ :id, :enabled, :cadence_cron, config: {} ]
    )
  end

  # Steps arrive as nested attributes for the steps the form shows. Any step
  # missing from the payload stays as-is; we never delete a step from a plan
  # (disabling it is what turns it off).
  def resourced_params
    plan_params
  end

  # The chain is always the full canonical order; a step that is absent from
  # the DB yet belongs in the chain gets built disabled, so the edit form is
  # complete and misses never silently drop out of the chain.
  def ensure_all_steps_present
    existing = @plan.maintenance_steps.map(&:operation)
    MaintenancePlan::CANONICAL_ORDER.each_with_index do |operation, position|
      next if existing.include?(operation)

      @plan.maintenance_steps.build(operation: operation, position: position, enabled: false)
    end
  end
end
