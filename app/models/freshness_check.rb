# A single freshness measurement for a table, recording the status the table
# had at the moment it was checked.
class FreshnessCheck < ApplicationRecord
  STATUSES = %w[ok warning late error no_data].freeze

  belongs_to :iceberg_table

  scope :latest, -> { order(checked_at: :desc) }
end
