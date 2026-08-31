# A scheduled maintenance routine for a single table: a cron schedule plus an
# ordered chain of maintenance steps that together describe what to run.
class MaintenancePlan < ApplicationRecord
  # Default order. My reasoning, not verified in the docs - worth a review from
  # whoever knows your workload:
  #
  #   optimize            rewrites data files; the old ones stay trapped in
  #                       old snapshots
  #   expire_snapshots    releases the old snapshots, and only then do the old
  #                       data files stop being referenced
  #   optimize_manifests  consolidates manifests AFTER the expiry, so we do not
  #                       consolidate a manifest that would be discarded next
  #   remove_orphan_files sweeps last what is left unreferenced
  CANONICAL_ORDER = %w[optimize expire_snapshots optimize_manifests remove_orphan_files].freeze

  # The steps a freshly-created plan runs by default: the safe, non-destructive
  # chain the operator gets when hitting "run now" on a table without a plan.
  DEFAULT_ENABLED_STEPS = %w[optimize expire_snapshots].freeze
  DEFAULT_CRON = "0 2 * * *"

  belongs_to :iceberg_table
  belongs_to :maintenance_policy, optional: true
  has_many :maintenance_steps, -> { order(:position) }, dependent: :destroy
  has_many :execution_histories, dependent: :destroy

  accepts_nested_attributes_for :maintenance_steps, allow_destroy: false

  validates :cron, presence: true
  validate  :cron_is_parseable

  scope :dispatchable, -> { where(is_paused: false) }

  # Builds a plan for a table with the full canonical step chain, enabling only
  # the default steps. Used by the operator "run now" path when a table has no
  # plan yet.
  # @param table [IcebergTable] the table to own the plan
  # @return [MaintenancePlan] the persisted plan with its steps
  def self.create_default_for!(table)
    plan = create!(iceberg_table: table, cron: DEFAULT_CRON)
    CANONICAL_ORDER.each_with_index do |operation, position|
      plan.maintenance_steps.create!(
        operation: operation,
        position: position,
        enabled: DEFAULT_ENABLED_STEPS.include?(operation),
        config: {}
      )
    end
    plan
  end

  # Whether dispatch of this plan is paused.
  # @return [Boolean]
  def paused?
    is_paused
  end

  # The maintenance steps that are currently enabled.
  # @return [Array<MaintenanceStep>]
  def enabled_steps
    maintenance_steps.select(&:enabled)
  end

  # Whether the plan's cron matches the given instant.
  # @param time [Time] the instant to test, defaulting to now
  # @return [Boolean]
  def scheduled_at?(time = Time.current)
    parsed = Fugit::Cron.parse(cron)
    return false if parsed.nil?

    parsed.match?(time.change(sec: 0, usec: 0))
  end

  # Typical duration of the recent successful runs - what replaces the guess
  # the old design required.
  def typical_duration
    durations = execution_histories.where(status: "success")
                                   .where.not(started_at: nil, finished_at: nil)
                                   .order(started_at: :desc).limit(10)
                                   .map { |e| e.finished_at - e.started_at }
    return nil if durations.empty?

    durations.sum / durations.size
  end

  # Batched typical durations for multiple plans in a bounded number of queries.
  # Returns a Hash mapping plan_id to the average duration (Float) or nil.
  # @param plan_ids [Array<Integer>] the plan ids to compute for
  # @return [Hash{Integer => Float}]
  def self.typical_durations_for(plan_ids)
    return {} if plan_ids.empty?

    rows = ExecutionHistory
             .where(maintenance_plan_id: plan_ids, status: "success")
             .where.not(started_at: nil, finished_at: nil)
             .select(:maintenance_plan_id, :started_at, :finished_at)
             .order(started_at: :desc)

    # Keep only the 10 most recent per plan
    counts = Hash.new(0)
    sums = Hash.new(0.0)

    rows.each do |row|
      next if counts[row.maintenance_plan_id] >= 10

      counts[row.maintenance_plan_id] += 1
      sums[row.maintenance_plan_id] += row.finished_at - row.started_at
    end

    counts.each_with_object({}) do |(plan_id, count), hash|
      hash[plan_id] = sums[plan_id] / count
    end
  end

  private

  # Validates that cron is a parseable expression, adding an error otherwise.
  def cron_is_parseable
    return if cron.blank?

    errors.add(:cron, "is not a valid cron expression") if Fugit::Cron.parse(cron).nil?
  end
end
