class MaintenanceSchedule < ApplicationRecord
  OPERATIONS = %w[optimize expire_snapshots remove_orphan_files optimize_manifests].freeze

  belongs_to :iceberg_table
  has_many :execution_histories, dependent: :destroy

  enum :operation, OPERATIONS.to_h { |o| [ o, o ] }
  scope :dispatchable, -> { where(is_paused: false) }

  validates :operation, presence: true, inclusion: { in: OPERATIONS }
  validates :operation, uniqueness: { scope: :iceberg_table_id }
  validates :cron, presence: true
  validate :cron_is_parseable
  validate :configuration_matches_operation
  before_validation :compact_config

  # True when the schedule's cron matches the given instant.
  def scheduled_at?(time = Time.current)
    parsed = Fugit::Cron.parse(cron)
    return false if parsed.nil?

    parsed.match?(time.change(sec: 0, usec: 0))
  end

  def paused?
    is_paused
  end

  private

  def cron_is_parseable
    return if cron.blank?

    errors.add(:cron, "is not a valid cron expression") if Fugit::Cron.parse(cron).nil?
  end

  def compact_config
    return if config.blank?

    self.config = config.reject { |_key, value| value.blank? }
  end

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
    value.blank? || value.match?(/\A\d+(?:\.\d+)?[KMGTP]?B\z/)
  end

  def valid_duration?(value)
    value.blank? || value.match?(/\A\d+(ms|s|m|h|d)\z/)
  end
end
