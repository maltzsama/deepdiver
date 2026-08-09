# Reusable maintenance rule, applicable to N tables at once.
#
# Motivation: with 100+ tables and 4 operations, creating schedules by hand
# becomes hundreds of forms. A policy ("streaming: optimize every 6h") applied
# in bulk solves that, and editing the policy syncs every schedule derived
# from it.
#
# Deliberate scope: ONE operation per policy, matching schedule granularity.
# For a full "streaming" setup, create one policy per operation. A
# multi-operation policy would need a child table and does not pay for itself
# now.
class MaintenancePolicy < ApplicationRecord
  has_many :maintenance_schedules, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :operation, presence: true, inclusion: { in: MaintenanceSchedule::OPERATIONS }
  validates :cron, presence: true
  validate :cron_is_parseable

  before_validation :compact_config

  # Creates (or updates) schedules for the given tables.
  # Never steals a schedule that already belongs to another policy.
  def apply_to!(tables)
    created = 0
    updated = 0
    skipped = 0

    tables.each do |table|
      schedule = MaintenanceSchedule.find_by(iceberg_table: table, operation: operation)

      if schedule.nil?
        MaintenanceSchedule.create!(
          iceberg_table: table, operation: operation,
          cron: cron, config: config, maintenance_policy: self
        )
        created += 1
      elsif schedule.maintenance_policy_id.nil? || schedule.maintenance_policy_id == id
        schedule.update!(cron: cron, config: config, maintenance_policy: self)
        updated += 1
      else
        skipped += 1
      end
    end

    { created: created, updated: updated, skipped: skipped }
  end

  # Reapplies cron/config to the schedules already derived from this policy.
  # Does NOT touch is_paused: a pause from repeated failures is operational
  # information and must not be wiped by a policy edit.
  def propagate!
    maintenance_schedules.each { |s| s.update!(cron: cron, config: config) }
    maintenance_schedules.size
  end

  private

  def compact_config
    return if config.blank?

    self.config = config.reject { |_key, value| value.blank? }
  end

  def cron_is_parseable
    return if cron.blank?

    errors.add(:cron, "is not a valid cron expression") if Fugit::Cron.parse(cron).nil?
  end
end
