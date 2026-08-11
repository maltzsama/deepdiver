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

  belongs_to :iceberg_table
  belongs_to :maintenance_policy, optional: true
  has_many :maintenance_steps, -> { order(:position) }, dependent: :destroy
  has_many :execution_histories, dependent: :destroy

  accepts_nested_attributes_for :maintenance_steps, allow_destroy: false

  validates :cron, presence: true
  validate  :cron_is_parseable

  scope :dispatchable, -> { where(is_paused: false) }

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

  private

  # Validates that cron is a parseable expression, adding an error otherwise.
  def cron_is_parseable
    return if cron.blank?

    errors.add(:cron, "is not a valid cron expression") if Fugit::Cron.parse(cron).nil?
  end
end
