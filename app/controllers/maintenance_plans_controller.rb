# Manages maintenance plans for iceberg tables: listing, viewing, editing, and
# controlling plans (run, pause, resume). Each action authorizes with Pundit;
# set_plan loads the plan for the member actions.
class MaintenancePlansController < ApplicationController
  before_action :set_plan, only: %i[show edit update run pause resume]

  # Lists all maintenance plans with their table and policy, ordered by id.
  def index
    authorize MaintenancePlan
    @plans = MaintenancePlan.includes(:iceberg_table, :maintenance_policy).order(:id)
    @pagy, @plans = pagy(@plans)
  end

  # Shows a single maintenance plan.
  def show
    authorize @plan
  end

  # Renders the new plan form with a table selector and default steps.
  def new
    authorize MaintenancePlan
    @plan = MaintenancePlan.new
    @plan.iceberg_table_id = params.dig(:maintenance_plan, :iceberg_table_id)
    @plan.cron = MaintenancePlan::DEFAULT_CRON
    MaintenancePlan::CANONICAL_ORDER.each_with_index do |operation, position|
      @plan.maintenance_steps.build(
        operation: operation, position: position,
        enabled: MaintenancePlan::DEFAULT_ENABLED_STEPS.include?(operation)
      )
    end
    @tables = IcebergTable.includes(:catalog).order(:namespace, :name)
  end

  # Creates a plan for the selected table. If the table already has a plan,
  # redirects to the existing plan's edit form instead.
  def create
    authorize MaintenancePlan
    table = IcebergTable.find(params[:maintenance_plan][:iceberg_table_id])
    existing = MaintenancePlan.find_by(iceberg_table: table)

    if existing
      redirect_to edit_maintenance_plan_path(existing), notice: t("plans.notices.already_exists")
      return
    end

    @plan = MaintenancePlan.new(plan_params.merge(iceberg_table: table))

    if @plan.save
      redirect_to @plan, notice: t("plans.notices.created")
    else
      @tables = IcebergTable.includes(:catalog).order(:namespace, :name)
      render :new, status: :unprocessable_content
    end
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
      redirect_to @plan, notice: t("plans.notices.updated")
    else
      ensure_all_steps_present
      render :edit, status: :unprocessable_content
    end
  end

  # Enqueues maintenance for the plan through the orchestrator and redirects.
  def run
    authorize @plan, :run?
    MaintenanceOrchestrator.run_plan(@plan.id, force: true)
    redirect_to @plan, notice: t("plans.notices.enqueued")
  end

  # Pauses the plan and redirects back to it.
  def pause
    authorize @plan, :pause?
    @plan.update!(is_paused: true)
    redirect_to @plan, notice: t("plans.notices.paused")
  end

  # Resumes a paused plan, clearing failure and review state, then redirects.
  def resume
    authorize @plan, :resume?
    @plan.update!(is_paused: false, consecutive_failures: 0, needs_review: false)
    redirect_to @plan, notice: t("plans.notices.resumed")
  end

  private

  # Loads the maintenance plan for the current request.
  def set_plan
    @plan = MaintenancePlan.find(params[:id])
  end

  # Strong parameters for the plan: the cron and the form's maintenance steps.
  def plan_params
    params.require(:maintenance_plan).permit(
      :cron, :iceberg_table_id,
      maintenance_steps_attributes: [
        :id, :enabled, :cadence_cron,
        config: %i[file_size_threshold retention_threshold snapshot_ids where]
      ]
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
