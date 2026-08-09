# How many executions need the Trino engine right now. While it is above zero,
# the engine stays up.
#
# An execution waiting to retry a commit conflict COUNTS as demand - that is
# what made awaiting_retry unnecessary.
module TrinoDemand
  ACTIVE_STATUSES = %w[pending running].freeze
  STALE_AFTER = 15.minutes

  module_function

  def count
    reap_orphans!
    ExecutionHistory.where(status: ACTIVE_STATUSES).count +
      FreshnessRun.where(status: %w[pending running]).count
  end

  def any? = count.positive?

  def none? = count.zero?

  # An execution "alive" without a heartbeat for too long lost its coordinator
  # together with the query. There is nothing to recover: record the failure
  # and free the lock.
  def reap_orphans!
    ExecutionHistory
      .where(status: "running")
      .where(last_heartbeat_at: ...STALE_AFTER.ago)
      .find_each do |execution|
        ExecutionFailureHandler.handle(
          execution,
          "Trino coordinator lost during execution (no heartbeat for #{STALE_AFTER.inspect})"
        )
      end
  end
end
