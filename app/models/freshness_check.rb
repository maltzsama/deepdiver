class FreshnessCheck < ApplicationRecord
  STATUSES = %w[ok warning late error no_data].freeze

  belongs_to :iceberg_table

  scope :latest, -> { order(checked_at: :desc) }
end
