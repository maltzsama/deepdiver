class TrinoEngineState < ApplicationRecord
  STATUSES = %w[down starting up draining stopping failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :status_changed_at, presence: true
end
