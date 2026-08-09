class ExecutionHistory < ApplicationRecord
  STATUSES = %w[pending running success failed].freeze

  # STEPS kept for the legacy step-chain rendering; current_step now holds the
  # name of the chain step in flight (an operation) or a lifecycle label.
  STEPS = %w[start scale_up executing_sql scale_down done].freeze

  belongs_to :maintenance_schedule, optional: true
  belongs_to :maintenance_plan, optional: true
  belongs_to :iceberg_table
  has_many :execution_steps, dependent: :destroy

  enum :status, STATUSES.to_h { |s| [ s, s ] }

  scope :latest, -> { order(created_at: :desc) }

  before_validation :set_iceberg_table_id

  def failed?
    status == "failed"
  end

  def finished?
    %w[success failed].include?(status)
  end

  def duration
    return nil if started_at.nil? || finished_at.nil?

    finished_at - started_at
  end

  # Human label of what the execution ran: the chain's enabled steps for a
  # plan, the legacy schedule operation otherwise.
  def operation_label
    if maintenance_plan
      steps = maintenance_plan.enabled_steps
      steps = maintenance_plan.maintenance_steps if steps.empty?
      steps.map(&:operation).join(" + ")
    else
      maintenance_schedule&.operation || current_step
    end
  end

  private

  def set_iceberg_table_id
    self.iceberg_table_id ||= maintenance_schedule&.iceberg_table_id || maintenance_plan&.iceberg_table_id
  end
end
