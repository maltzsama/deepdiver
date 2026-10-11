# How many executions need the Trino engine right now.
# While it is above zero, the engine stays up.
module TrinoDemand
  ACTIVE_EXECUTION_STATUSES = %w[pending running].freeze
  STALE_AFTER = ENV.fetch("TRINO_HEARTBEAT_STALE_MINUTES", "15").to_i.minutes

  # A "pending" execution is demand too, so one whose dispatch never arrived
  # (worker down when it was enqueued, queue row lost, primary commit rolled
  # back) held the engine up forever - reaping only looked at "running".
  #
  # Deliberately well above the whole start path: READY_TIMEOUT x
  # MAX_START_ATTEMPTS plus slack, so a run legitimately waiting for a slow
  # engine start is never reaped. A failed start already fails its pending
  # executions through SuperviseEngineStartJob#fail_pending_executions!.
  PENDING_STALE_AFTER = ENV.fetch("TRINO_PENDING_STALE_MINUTES", "45").to_i.minutes

  module_function

  # Total executions currently needing the engine, after reaping orphaned
  # ones.
  # @return [Integer]
  def count
    reap_orphans!
    maintenance_count
  end

  # Number of maintenance executions currently pending or running.
  # @return [Integer]
  def maintenance_count = ExecutionHistory.where(status: ACTIVE_EXECUTION_STATUSES).count

  # Whether anything currently needs the engine.
  # @return [Boolean]
  def any? = count.positive?

  # Detail for the "in progress" screen.
  def breakdown
    { maintenance: maintenance_count }
  end

  # A "live" execution without a heartbeat for too long lost its coordinator
  # together with the query.
  def reap_orphans!
    ExecutionHistory
      .where(status: "running")
      .where("COALESCE(last_heartbeat_at, started_at) < ?", STALE_AFTER.ago)
      .find_each do |execution|
        ExecutionFailureHandler.handle(execution,
                                       "Trino coordinator lost during execution (no heartbeat for #{STALE_AFTER.inspect})")
      end

    ExecutionHistory
      .where(status: "pending")
      .where("COALESCE(started_at, created_at) < ?", PENDING_STALE_AFTER.ago)
      .find_each do |execution|
        ExecutionFailureHandler.handle(execution,
                                       "dispatch never arrived (pending for over #{PENDING_STALE_AFTER.inspect})")
      end
  end
end
