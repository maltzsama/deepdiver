# A single step inside an execution history, tracking the status and timing of
# one chain operation.
class ExecutionStep < ApplicationRecord
  STATUSES = %w[pending running succeeded failed skipped blocked].freeze

  belongs_to :execution_history
  belongs_to :maintenance_step, optional: true

  enum :status, STATUSES.to_h { |s| [ s, s ] }

  validates :operation, presence: true

  # skip_reason holds CONFIGURATION reasons only ("step disabled", "outside
  # cadence", "chain aborted"). error_message holds operational failures ONLY.
  # A skipped/blocked step must never carry error_message.

  scope :blocked, -> { where(status: "blocked") }

  # Wall-clock duration of the step, when both start and end are known.
  # @return [Float, nil]
  def duration
    return nil if started_at.nil? || finished_at.nil?

    finished_at - started_at
  end
end
