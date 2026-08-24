# One step in a maintenance plan's chain, with its own cadence override and
# per-step configuration.
class MaintenanceStep < ApplicationRecord
  belongs_to :maintenance_plan

  validates :operation, presence: true, inclusion: { in: MaintenancePlan::CANONICAL_ORDER }
  validates :position, presence: true
  validate :cadence_cron_is_parseable
  validate :config_values_are_well_formed

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

  # A duration/threshold magnitude plus a unit, e.g. "7d", "128MB", "1.5GB".
  # These are interpolated straight into the ALTER TABLE ... EXECUTE statement,
  # so anything else is rejected instead of shipped as raw SQL.
  THRESHOLD_PATTERN = /\A\d+(?:\.\d+)?\s*[a-zA-Z]+\z/

  # Snapshot ids are interpolated into ARRAY[...] unquoted, so they must be
  # integers only - never SQL.
  SNAPSHOT_IDS_PATTERN = /\A\d+(?:\s*,\s*\d+)*\z/

  # Validates that config fields reaching the SQL builder are well formed,
  # rejecting anything that would otherwise be interpolated as raw SQL.
  def config_values_are_well_formed
    validate_threshold("file_size_threshold")
    validate_threshold("retention_threshold")
    validate_snapshot_ids
  end

  def validate_threshold(key)
    value = config[key]
    return if value.blank?
    return if value.to_s.match?(THRESHOLD_PATTERN)

    errors.add(:config, "#{key} must be a magnitude plus a unit (e.g. 7d, 128MB)")
  end

  def validate_snapshot_ids
    value = config["snapshot_ids"]
    return if value.blank?
    return if value.to_s.strip.match?(SNAPSHOT_IDS_PATTERN)

    errors.add(:config, "snapshot_ids must be a comma-separated list of integers")
  end

  # Validates that cadence_cron is parseable and that it ever aligns with the
  # plan's cron, so the step cannot silently never run.
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
