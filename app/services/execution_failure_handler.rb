# Circuit breaker: marks an execution as failed, tracks consecutive failures on
# the maintenance plan (pausing it after the plan's threshold), records the
# failure as an error event, and frees the per-table lock. The engine lifecycle
# is the supervisor's job.
class ExecutionFailureHandler
  # Convenience entry point: builds a handler and runs it.
  #
  # @param execution [ExecutionHistory] the failed execution
  # @param error_message [String] the failure message
  # @param scale_down [Boolean] whether to release the per-table lock
  # @return [ExecutionHistory] the handled execution
  def self.handle(execution, error_message, scale_down: true)
    new(execution, error_message, scale_down: scale_down).call
  end

  # Creates the handler for a failed execution.
  #
  # @param execution [ExecutionHistory] the failed execution
  # @param error_message [String] the failure message
  # @param scale_down [Boolean] whether to release the per-table lock
  def initialize(execution, error_message, scale_down:)
    @execution = execution
    @error_message = error_message
    @scale_down = scale_down
    @plan = execution.maintenance_plan
    @table = execution.iceberg_table
  end

  # Runs the failure handling sequence and returns the updated execution.
  #
  # @return [ExecutionHistory] the updated execution
  def call
    fail_execution
    increment_and_maybe_pause
    release_table_lock

    @execution
  end

  private

  # Marks the execution failed and records an error event.
  TERMINAL_STATUSES = %w[failed success skipped].freeze

  def fail_execution
    return if TERMINAL_STATUSES.include?(@execution.status)

    @execution.update!(status: :failed, error_message: @error_message)
    block_pending_steps!

    ErrorEvent.record(catalog: @table&.catalog, schema: @table&.namespace,
                      table: @table&.name, operation: "execution",
                      source_system: "engine", error_class: "ExecutionFailure",
                      message: @error_message)
  end

  # Steps still pending when the chain aborts will never run. "pending" means
  # "will run" - leaving them pending would count dead work as queued demand.
  # Blocked is neutral for health scoring: it is the same failure counted once,
  # not an independent one.
  def block_pending_steps!
    reason = "chain aborted by #{@execution.current_step.presence || 'previous step'} failure"
    @execution.execution_steps.where(status: "pending").update_all(
      status: "blocked", skip_reason: reason, updated_at: Time.current
    )
  end

  # Increments the plan's consecutive-failure counter, pausing it past the threshold.
  def increment_and_maybe_pause
    return if @plan.nil?

    @plan.increment!(:consecutive_failures)

    return unless @plan.consecutive_failures >= (@plan.auto_pause_after || 3)

    @plan.update!(is_paused: true)
    Rails.logger.warn("Plan #{@plan.id} paused after #{@plan.consecutive_failures} consecutive failures")
  end

  # The engine is NOT brought down per execution - that is the supervisor's
  # job, driven by demand. Only the per-table lock is freed here.
  def release_table_lock
    TableLock.release(@execution) if @scale_down
  end
end
