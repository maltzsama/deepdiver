# Reusable maintenance rule, applicable to N tables at once.
#
# Motivation: with 100+ tables, creating plans by hand becomes hundreds of
# forms. A policy ("streaming: optimize every 6h") applied in bulk solves that,
# and editing the policy syncs every plan derived from it.
#
# A policy defines the WHOLE chain: cron, which steps enter, and each step's
# configuration (steps_config).
class MaintenancePolicy < ApplicationRecord
  has_many :maintenance_plans, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :cron, presence: true
  validate :cron_is_parseable

  # Creates (or updates) the maintenance PLAN of each given table.
  # Never steals a plan that already belongs to another policy.
  def apply_to!(tables)
    created = 0
    updated = 0
    skipped = 0

    tables.each do |table|
      plan = MaintenancePlan.find_or_initialize_by(iceberg_table: table)

      if plan.maintenance_policy_id.nil? || plan.maintenance_policy_id == id
        new_record = plan.new_record?
        plan.cron = cron
        plan.maintenance_policy = self
        plan.save!
        sync_steps(plan)
        new_record ? created += 1 : updated += 1
      else
        skipped += 1
      end
    end

    { created: created, updated: updated, skipped: skipped }
  end

  # Reapplies cron and step configuration to the plans already derived from
  # this policy. Does NOT touch is_paused: a pause from repeated failures is
  # operational information and must not be wiped by a policy edit.
  def propagate!
    maintenance_plans.each do |plan|
      plan.update!(cron: cron)
      sync_steps(plan)
    end
    maintenance_plans.size
  end

  private

  def sync_steps(plan)
    MaintenancePlan::CANONICAL_ORDER.each_with_index do |operation, position|
      step_config = steps_config[operation] || {}
      step = plan.maintenance_steps.find_or_initialize_by(operation: operation)
      step.position = position
      # Absent "enabled" means "not touched": keep the default (on). The form
      # always sends an explicit 0/1, so an unchecked box disables the step.
      step.enabled = step_config.key?("enabled") ? step_config["enabled"].to_s == "1" : true
      step.config = step_config.except("enabled")
      step.save!
    end
  end

  def cron_is_parseable
    return if cron.blank?

    errors.add(:cron, "is not a valid cron expression") if Fugit::Cron.parse(cron).nil?
  end
end
