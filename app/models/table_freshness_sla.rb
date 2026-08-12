# The freshness contract for a table: which timestamp column is authoritative,
# how it is encoded, and how stale the table may get before warning/late. Also
# carries the progressive severity bands and the alert destination (Slack
# #channel and/or email recipients) for this table's freshness alerts.
class TableFreshnessSla < ApplicationRecord
  TIMESTAMP_TYPES = %w[timestamp_tz timestamp_ntz epoch_seconds epoch_millis epoch_micros].freeze
  STATUSES = %w[unknown ok warning late error no_data].freeze
  SEVERITIES = %w[warning severe critical].freeze
  SEVERITY_LEVEL = { "warning" => 1, "severe" => 2, "critical" => 3 }.freeze

  belongs_to :iceberg_table
  has_many :freshness_checks, dependent: :destroy

  validates :timestamp_column, presence: true
  validates :timestamp_type, inclusion: { in: TIMESTAMP_TYPES }
  validates :source_timezone, presence: true
  validates :sla_minutes, numericality: { greater_than: 0 }
  validates :warning_at_percent, numericality: { only_integer: true, in: 1..100 }
  validates :partition_lookback, numericality: { only_integer: true, greater_than: 0 }
  validates :warning_after_minutes, :severe_after_minutes, :critical_after_minutes,
            numericality: { only_integer: true, greater_than: 0 }
  validate :severity_thresholds_ordered

  scope :enabled, -> { where(enabled: true) }

  # Whether the SLA has anywhere to send alerts to.
  #
  # @return [Boolean]
  def alert_configured?
    slack_channel.present? || email_to.present?
  end

  private

  # Progressive severity only makes sense if the bands go up: warning first,
  # then severe, then critical.
  def severity_thresholds_ordered
    return if warning_after_minutes.nil? || severe_after_minutes.nil? || critical_after_minutes.nil?

    unless severe_after_minutes > warning_after_minutes
      errors.add(:severe_after_minutes, :must_exceed_warning)
    end
    unless critical_after_minutes > severe_after_minutes
      errors.add(:critical_after_minutes, :must_exceed_severe)
    end
  end
end
