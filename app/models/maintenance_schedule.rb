class MaintenanceSchedule < ApplicationRecord
  OPERATIONS = %w[optimize expire_snapshots remove_orphan_files rewrite_manifests].freeze

  # Standard 5-field cron expression: minute hour day-of-month month day-of-week.
  CRON_PATTERN = /\A(\*|\d+|\d+\/\d+|\d+(?:-\d+)?(?:,[0-9*\/-]+)*|\*\/\d+)(\s+\S+){4}\z/

  belongs_to :iceberg_table
  has_many :execution_histories, dependent: :destroy

  enum :operation, OPERATIONS.to_h { |o| [ o, o ] }
  scope :dispatchable, -> { where(is_paused: false) }

  validates :operation, presence: true, inclusion: { in: OPERATIONS }
  validates :operation, uniqueness: { scope: :iceberg_table_id }
  validates :cron, presence: true, format: { with: CRON_PATTERN }
  validate :configuration_matches_operation

  # True when the schedule's cron matches the given instant.
  def scheduled_at?(time = Time.current)
    !cron.blank? && (Fugit::Cron.parse(cron)&.match?(time.change(sec: 0, usec: 0)) || false)
  end

  def paused?
    is_paused
  end

  private

  def configuration_matches_operation
    return if config.nil? || config.empty?

    case operation
    when "optimize"
      errors.add(:config, "file_size_threshold must be a size string") unless valid_size?(config["file_size_threshold"])
    when "expire_snapshots", "remove_orphan_files"
      errors.add(:config, "retention_threshold must be a duration string") unless valid_duration?(config["retention_threshold"])
    end
  end

  def valid_size?(value)
    value.nil? || value.match?(/\A\d+(?:\.\d+)?[KMGTP]?B\z/)
  end

  def valid_duration?(value)
    value.nil? || value.match?(/\A\d+(ms|s|m|h|d)\z/)
  end
end
