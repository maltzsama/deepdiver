class ExecutionHistory < ApplicationRecord
  STATUSES = %w[pending running success failed].freeze
  STEPS = %w[start scale_up executing_sql scale_down done].freeze

  belongs_to :maintenance_schedule

  enum :status, STATUSES.to_h { |s| [ s, s ] }
  enum :current_step, STEPS.to_h { |s| [ s, s ] }

  scope :latest, -> { order(created_at: :desc) }

  def failed?
    status == "failed"
  end

  def finished?
    %w[success failed].include?(status)
  end

  def awaiting_retry?
    awaiting_retry == true
  end
end
