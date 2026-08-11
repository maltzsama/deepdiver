# The single source of truth for the Trino engine's current lifecycle state,
# written by the engine controller as it boots and drains.
class TrinoEngineState < ApplicationRecord
  STATUSES = %w[down starting up draining stopping failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :status_changed_at, presence: true
end
