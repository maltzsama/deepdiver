class MaintenanceStep < ApplicationRecord
  belongs_to :maintenance_plan

  validates :operation, presence: true, inclusion: { in: MaintenancePlan::CANONICAL_ORDER }
  validates :position, presence: true
  validate :cadence_cron_is_parseable

  # Due at this dispatch?
  #
  # Without cadence_cron it always runs - the step follows the plan's rhythm.
  # With cadence_cron it runs when the cron matches the dispatch instant.
  def due_at?(time)
    return true if cadence_cron.blank?

    parsed = Fugit::Cron.parse(cadence_cron)
    return true if parsed.nil?

    parsed.match?(time.change(sec: 0, usec: 0))
  end

  private

  def cadence_cron_is_parseable
    return if cadence_cron.blank?

    parsed = Fugit::Cron.parse(cadence_cron)
    return errors.add(:cadence_cron, "is not a valid cron expression") if parsed.nil?

    validate_alignment(parsed)
  end

  # A step whose cadence never coincides with the plan's dispatch never runs -
  # and fails silently. Reject it at validation, not in production.
  def validate_alignment(parsed)
    plan_cron = Fugit::Cron.parse(maintenance_plan&.cron)
    return if plan_cron.nil?

    probe = Time.current.beginning_of_day
    72.times do
      nxt = plan_cron.next_time(probe).to_t
      return if parsed.match?(nxt.change(sec: 0, usec: 0))

      probe = nxt
    end

    errors.add(:cadence_cron,
               "never coincides with the plan cron (#{maintenance_plan.cron}) - this step would never run")
  end
end
