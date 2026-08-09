class ExecutionHistory < ApplicationRecord
  STATUSES = %w[pending running success failed].freeze
  STEPS = %w[start scale_up executing_sql scale_down done].freeze

  belongs_to :maintenance_schedule
  belongs_to :iceberg_table

  enum :status, STATUSES.to_h { |s| [ s, s ] }
  enum :current_step, STEPS.to_h { |s| [ s, s ] }

  scope :latest, -> { order(created_at: :desc) }

  before_validation :set_iceberg_table_id

  def failed?
    status == "failed"
  end

  def finished?
    %w[success failed].include?(status)
  end

  private

  def set_iceberg_table_id
    self.iceberg_table_id ||= maintenance_schedule&.iceberg_table_id
  end
end
