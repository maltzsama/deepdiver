# A single maintenance operation scheduled on a cron for one table: the legacy
# schedule form, superseded by maintenance plans.
class MaintenanceSchedule < ApplicationRecord
  OPERATIONS = %w[optimize expire_snapshots remove_orphan_files optimize_manifests].freeze

  belongs_to :iceberg_table
  belongs_to :maintenance_policy, optional: true
  has_many :execution_histories, dependent: :destroy

  enum :operation, OPERATIONS.to_h { |o| [ o, o ] }

  validates :operation, presence: true, inclusion: { in: OPERATIONS }
  validates :operation, uniqueness: { scope: :iceberg_table_id }
  validates :cron, presence: true
  validate :cron_is_parseable
  validate :configuration_matches_operation
  before_validation :compact_config

  # Whether dispatch of this schedule is paused.
  # @return [Boolean]
  def paused?
    is_paused
  end

  private

  # Validates that cron is a parseable expression, adding an error otherwise.
  def cron_is_parseable
    return if cron.blank?

    errors.add(:cron, "is not a valid cron expression") if Fugit::Cron.parse(cron).nil?
  end

  # Removes blank entries from the configuration hash before saving.
  def compact_config
    return if config.blank?

    self.config = config.reject { |_key, value| value.blank? }
  end

  # Validates that the configuration keys match what the selected operation
  # expects, adding an error for invalid threshold values.
  def configuration_matches_operation
    return if config.nil? || config.empty?

    case operation
    when "optimize"
      errors.add(:config, "file_size_threshold must be a size string") unless valid_size?(config["file_size_threshold"])
    when "expire_snapshots", "remove_orphan_files"
      errors.add(:config, "retention_threshold must be a duration string") unless valid_duration?(config["retention_threshold"])
    end
  end

  # Whether the value is a valid size string (e.g. "2GB") or blank.
  # @param value [String, nil] the value to validate
  # @return [Boolean]
  def valid_size?(value)
    value.blank? || value.match?(/\A\d+(?:\.\d+)?[KMGTP]?B\z/)
  end

  # Whether the value is a valid duration string (e.g. "24h") or blank.
  # @param value [String, nil] the value to validate
  # @return [Boolean]
  def valid_duration?(value)
    value.blank? || value.match?(/\A\d+(ms|s|m|h|d)\z/)
  end
end
