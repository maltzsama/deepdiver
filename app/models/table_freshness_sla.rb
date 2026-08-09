class TableFreshnessSla < ApplicationRecord
  TIMESTAMP_TYPES = %w[timestamp_tz timestamp_ntz epoch_seconds epoch_millis epoch_micros].freeze
  STATUSES = %w[unknown ok warning late error no_data].freeze

  belongs_to :iceberg_table
  has_many :freshness_checks, dependent: :destroy

  validates :timestamp_column, presence: true
  validates :timestamp_type, inclusion: { in: TIMESTAMP_TYPES }
  validates :source_timezone, presence: true
  validates :sla_minutes, numericality: { greater_than: 0 }
  validates :warning_at_percent, numericality: { only_integer: true, in: 1..100 }
  validates :partition_lookback, numericality: { only_integer: true, greater_than: 0 }

  scope :enabled, -> { where(enabled: true) }
end
