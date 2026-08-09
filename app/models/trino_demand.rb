# How many executions and freshness sweeps need the Trino engine right now.
# While it is above zero, the engine stays up.
module TrinoDemand
  ACTIVE_EXECUTION_STATUSES = %w[pending running].freeze
  ACTIVE_RUN_STATUSES = %w[pending running].freeze
  STALE_AFTER = 15.minutes

  module_function

  def count
    reap_orphans!
    maintenance_count + freshness_count
  end

  def maintenance_count = ExecutionHistory.where(status: ACTIVE_EXECUTION_STATUSES).count

  def freshness_count = FreshnessRun.where(status: ACTIVE_RUN_STATUSES).count

  def any? = count.positive?

  # Detail for the "in progress" screen.
  def breakdown
    { maintenance: maintenance_count, freshness: freshness_count }
  end

  # A "live" execution without a heartbeat for too long lost its coordinator
  # together with the query; a freshness sweep whose worker died is the same.
  def reap_orphans!
    ExecutionHistory
      .where(status: "running")
      .where(last_heartbeat_at: ...STALE_AFTER.ago)
      .find_each do |execution|
        ExecutionFailureHandler.handle(execution,
                                       "Trino coordinator lost during execution (no heartbeat for #{STALE_AFTER.inspect})")
      end

    FreshnessRun
      .where(status: "running")
      .where(started_at: ...STALE_AFTER.ago)
      .find_each do |run|
        run.update!(status: "failed", finished_at: Time.current, error_message: "sweep interrupted")
      end
  end
end
