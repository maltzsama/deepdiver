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
  # Shared with the engine config's retention floors, which are compared
  # against these values.
  THRESHOLD_PATTERN = TrinoDuration::PATTERN

  # Snapshot ids are interpolated into ARRAY[...] unquoted, so they must be
  # integers only - never SQL.
  SNAPSHOT_IDS_PATTERN = /\A\d+(?:\s*,\s*\d+)*\z/

  # WHERE predicates are interpolated verbatim into ALTER TABLE ... EXECUTE
  # statements. This allows common SQL predicate syntax (comparisons, boolean
  # operators, parentheses, column refs, string/numeric literals) while
  # rejecting stacked queries, DDL, and comment-based injection.
  WHERE_PREDICATE_PATTERN = /\A[\sa-zA-Z0-9_\.'"()<>=!|&%,*:+\/-]+\z/
  WHERE_SQL_COMMENTS = /(?:--\s|\/\*)/

  # Validates that config fields reaching the SQL builder are well formed,
  # rejecting anything that would otherwise be interpolated as raw SQL.
  def config_values_are_well_formed
    validate_threshold("file_size_threshold")
    validate_threshold("retention_threshold")
    validate_snapshot_ids
    validate_where_predicate
    validate_retention_above_engine_floor
  end

  # The column defaults to {}, but a form that submits a blank config sends nil
  # - and validation must reject bad input, not raise NoMethodError on it.
  def config_hash
    config.is_a?(Hash) ? config : {}
  end

  def validate_threshold(key)
    value = config_hash[key]
    return if value.blank?
    return if value.to_s.match?(THRESHOLD_PATTERN)

    errors.add(:config, "#{key} must be a magnitude plus a unit (e.g. 7d, 128MB)")
  end

  def validate_snapshot_ids
    value = config_hash["snapshot_ids"]
    return if value.blank?
    return if value.to_s.strip.match?(SNAPSHOT_IDS_PATTERN)

    errors.add(:config, "snapshot_ids must be a comma-separated list of integers")
  end

  # Trino rejects a retention shorter than the connector's configured floor,
  # and it does so mid-chain, hours after the plan was saved. Both values are
  # known here, so the conflict is reported at save time instead - naming the
  # floor and where to change it.
  def validate_retention_above_engine_floor
    value = config_hash["retention_threshold"]
    return if value.blank?

    requested = TrinoDuration.to_seconds(value)
    return if requested.nil?

    floor = TrinoEngineConfig.instance.retention_floor_seconds(operation)
    return if floor.nil? || requested >= floor

    errors.add(:config, :retention_below_floor,
               requested: value.to_s,
               floor: engine_floor_label,
               operation: operation)
  end

  # The configured floor as the operator typed it, for the error message.
  def engine_floor_label
    config = TrinoEngineConfig.instance
    operation == "expire_snapshots" ? config.expire_snapshots_min_retention : config.remove_orphan_files_min_retention
  end

  def validate_where_predicate
    value = config_hash["where"]
    return if value.blank?
    return if value.to_s.strip.match?(WHERE_PREDICATE_PATTERN) && !value.to_s.match?(WHERE_SQL_COMMENTS)

    errors.add(:config, "where must be a valid SQL predicate (no stacked queries, DDL, or comments)")
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
