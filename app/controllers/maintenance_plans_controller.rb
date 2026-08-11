# Manages maintenance plans for iceberg tables: listing, viewing, editing, and
# controlling plans (run, pause, resume). Each action authorizes with Pundit;
# set_plan loads the plan for the member actions.
class MaintenancePlansController < ApplicationController
  before_action :set_plan, only: %i[show edit update run pause resume]

  # Lists all maintenance plans with their table and policy, ordered by id.
  def index
    authorize MaintenancePlan
    @plans = MaintenancePlan.includes(:iceberg_table, :maintenance_policy).order(:id)
  end

  # Shows a single maintenance plan.
  def show
    authorize @plan
  end

  # Renders the edit form, ensuring every canonical step is present for editing.
  def edit
    authorize @plan
    ensure_all_steps_present
  end

  # Updates the plan with the submitted nested steps and redirects to the plan,
  # or re-renders the edit form on validation failure.
  def update
    authorize @plan
    if @plan.update(resourced_params)
      redirect_to @plan, notice: "Plan updated."
    else
      ensure_all_steps_present
      render :edit, status: :unprocessable_content
    end
  end

  # Enqueues maintenance for the plan through the orchestrator and redirects.
  def run
    authorize @plan, :run?
    MaintenanceOrchestrator.run_plan(@plan.id)
    redirect_to @plan, notice: "Maintenance enqueued."
  end

  # Pauses the plan and redirects back to it.
  def pause
    authorize @plan, :pause?
    @plan.update!(is_paused: true)
    redirect_to @plan, notice: "Plan paused."
  end

  # Resumes a paused plan, clearing failure and review state, then redirects.
  def resume
    authorize @plan, :resume?
    @plan.update!(is_paused: false, consecutive_failures: 0, needs_review: false)
    redirect_to @plan, notice: "Plan resumed."
  end

  private

  # Loads the maintenance plan for the current request.
  def set_plan
    @plan = MaintenancePlan.find(params[:id])
  end

  # Strong parameters for the plan: the cron and the form's maintenance steps.
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
