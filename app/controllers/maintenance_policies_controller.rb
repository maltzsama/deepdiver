class MaintenancePoliciesController < ApplicationController
  before_action :require_admin!, except: %i[index show]
  before_action :set_policy, only: %i[show edit update destroy apply]

  def index
    @policies = MaintenancePolicy.order(:name)
  end

  def show
    @plans = @policy.maintenance_plans.includes(:iceberg_table)
    @candidates = IcebergTable.includes(:catalog).order(:namespace, :name)
    @apply_preview = preview_for(@policy, @candidates)
  end

  def new
    @policy = MaintenancePolicy.new
  end

  def create
    @policy = MaintenancePolicy.new(policy_params)

    if @policy.save
      redirect_to @policy, notice: "Policy created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @policy.update(policy_params)
      # Propagate to the plans derived from this policy.
      count = @policy.propagate!
      redirect_to @policy, notice: "Policy updated. #{count} plan(s) synced."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @policy.destroy
    redirect_to maintenance_policies_path, notice: "Policy deleted."
  end

  # Applies the policy to a set of tables at once, creating/updating their plans.
  def apply
    ids = Array(params[:iceberg_table_ids]).reject(&:blank?)
    result = @policy.apply_to!(IcebergTable.where(id: ids))

    notice = "#{result[:created]} plan(s) created, #{result[:updated]} updated."
    notice += " #{result[:skipped]} skipped (already managed by another policy)." if result[:skipped].positive?

    redirect_to @policy, notice: notice
  end

  private

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
          .permit(:name, :description, :cron, steps_config: {})
  end
end
