# One run of a maintenance plan or a legacy schedule operation against a table.
# Tracks status, timing, retries, and the individual chain steps executed.
class ExecutionHistory < ApplicationRecord
  STATUSES = %w[pending running success failed skipped].freeze

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

  # Whether the execution ended in failure.
  # @return [Boolean]
  def failed?
    status == "failed"
  end

  # Whether the execution has reached a terminal state.
  # @return [Boolean]
  def finished?
    %w[success failed skipped].include?(status)
  end

  # Whether the execution is currently running and has already been retried.
  # @return [Boolean]
  def retrying?
    status == "running" && retry_count.positive?
  end

  # Started_at of the chain step currently in flight, if any.
  def current_step_started_at
    execution_steps.select { |s| s.status == "running" }.first&.started_at
  end

  # Why a queued execution is not running yet.
  def waiting_reason
    TableLock.exists?(iceberg_table_id: iceberg_table_id) ? :lock : :engine
  end

  # Wall-clock duration of the execution, when both start and end are known.
  # @return [Float, nil]
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

  # Backfills iceberg_table_id from the maintenance_schedule or maintenance_plan
  # when it was not supplied directly.
  def set_iceberg_table_id
    self.iceberg_table_id ||= maintenance_schedule&.iceberg_table_id || maintenance_plan&.iceberg_table_id
  end
end
