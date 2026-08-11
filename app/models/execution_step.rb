# A single step inside an execution history, tracking the status and timing of
# one chain operation.
class ExecutionStep < ApplicationRecord
  STATUSES = %w[pending running succeeded failed skipped].freeze

  belongs_to :execution_history
  belongs_to :maintenance_step, optional: true

  enum :status, STATUSES.to_h { |s| [ s, s ] }

  validates :operation, presence: true

  # Wall-clock duration of the step, when both start and end are known.
  # @return [Float, nil]
  def duration
    return nil if started_at.nil? || finished_at.nil?

    finished_at - started_at
  end
end
