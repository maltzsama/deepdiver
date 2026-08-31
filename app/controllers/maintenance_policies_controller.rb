# Manages maintenance policies: reusable maintenance definitions that can be
# applied to many tables at once, creating or updating their plans. CRUD plus
# an apply action with a preview; each action authorizes with Pundit.
class MaintenancePoliciesController < ApplicationController
  before_action :set_policy, only: %i[show edit update destroy apply]

  # Lists all maintenance policies ordered by name.
  def index
    authorize MaintenancePolicy
    @policies = MaintenancePolicy.order(:name)
  end

  # Shows a policy with its derived plans, candidate tables, and a preview of
  # what applying the policy would do.
  def show
    authorize @policy
    @plans = @policy.maintenance_plans.includes(:iceberg_table)
    @candidates = IcebergTable.includes(:catalog, maintenance_plan: :maintenance_policy)
                              .order(:namespace, :name)
    @apply_preview = preview_for(@policy, @candidates)
  end

  # Renders the form for creating a maintenance policy.
  def new
    authorize MaintenancePolicy
    @policy = MaintenancePolicy.new
  end

  # Creates a policy and redirects to it, or re-renders the form on failure.
  def create
    authorize MaintenancePolicy
    @policy = MaintenancePolicy.new(policy_params)

    if @policy.save
      redirect_to @policy, notice: t("policies.notices.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  # Renders the edit form for a policy.
  def edit
    authorize @policy
  end

  # Updates the policy, propagates the change to its derived plans, and
  # redirects, or re-renders the form on failure.
  def update
    authorize @policy
    if @policy.update(policy_params)
      # Propagate to the plans derived from this policy.
      count = @policy.propagate!
      redirect_to @policy, notice: t("policies.notices.updated", count: count)
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Destroys the policy and redirects to the policies index.
  def destroy
    authorize @policy
    @policy.destroy
    redirect_to maintenance_policies_path, notice: t("policies.notices.destroyed")
  end

  # Applies the policy to a set of tables at once, creating/updating their plans.
  def apply
    authorize @policy, :apply?
    ids = Array(params[:iceberg_table_ids]).reject(&:blank?)
    result = @policy.apply_to!(IcebergTable.where(id: ids))

    notice = t("policies.notices.applied", created: result[:created], updated: result[:updated])
    notice += " #{result[:skipped]} #{t('policies.notices.skipped')}" if result[:skipped].positive?

    redirect_to @policy, notice: notice
  end

  # Bulk apply from the tables index: select tables → pick a policy → apply.
  def bulk_apply
    authorize MaintenancePolicy, :apply?
    policy = MaintenancePolicy.find(params[:policy_id])
    ids = Array(params[:iceberg_table_ids]).reject(&:blank?)

    if ids.empty?
      redirect_to iceberg_tables_path, alert: t("policies.notices.no_tables_selected")
      return
    end

    result = policy.apply_to!(IcebergTable.where(id: ids))

    notice = t("policies.notices.applied", created: result[:created], updated: result[:updated])
    notice += " #{result[:skipped]} #{t('policies.notices.skipped')}" if result[:skipped].positive?

    redirect_to iceberg_tables_path, notice: notice
  end

  private

  # Loads the maintenance policy for the current request.
  def set_policy
    @policy = MaintenancePolicy.find(params[:id])
  end

  # What applying this policy to the given tables would do.
  def preview_for(policy, tables)
    created = 0
    updated = 0
    skipped = []

    tables.each do |table|
      plan = table.maintenance_plan
      if plan.nil? || plan.maintenance_policy_id.nil? || plan.maintenance_policy_id == policy.id
        plan.nil? ? created += 1 : updated += 1
      else
        skipped << [ table.fully_qualified_name, plan.maintenance_policy.name ]
      end
    end

    { created: created, updated: updated, skipped: skipped }
  end

  def policy_params
    params.require(:maintenance_policy)
          .permit(:name, :description, :cron,
                  steps_config: %i[file_size_threshold retention_threshold snapshot_ids where])
  end
end
