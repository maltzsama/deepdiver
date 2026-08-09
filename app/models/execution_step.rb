class ExecutionStep < ApplicationRecord
  STATUSES = %w[pending running succeeded failed skipped].freeze

  belongs_to :execution_history
  belongs_to :maintenance_step, optional: true

  enum :status, STATUSES.to_h { |s| [ s, s ] }

  validates :operation, presence: true

  def duration
    return nil if started_at.nil? || finished_at.nil?

    finished_at - started_at
  end
end
