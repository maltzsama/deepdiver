# Circuit breaker: marks an execution as failed, tracks consecutive failures on
# the maintenance plan (pausing it after the plan's threshold), alerts Slack,
# and frees the per-table lock. The engine lifecycle is the supervisor's job.
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
    notify
    release_table_lock

    @execution
  end

  private

  # Marks the execution failed and records an error event.
  def fail_execution
    @execution.update!(status: :failed, error_message: @error_message)

    ErrorEvent.record(catalog: @table&.catalog, schema: @table&.namespace,
                      table: @table&.name, operation: "execution",
                      source_system: "engine", error_class: "ExecutionFailure",
                      message: @error_message)
  end

  # Increments the plan's consecutive-failure counter, pausing it past the threshold.
  def increment_and_maybe_pause
    return if @plan.nil?

    @plan.increment!(:consecutive_failures)

    return unless @plan.consecutive_failures >= (@plan.auto_pause_after || 3)

    @plan.update!(is_paused: true)
    Rails.logger.warn("Plan #{@plan.id} paused after #{@plan.consecutive_failures} consecutive failures")
  end

  # Sends a Slack alert for the failed maintenance.
  def notify
    SlackAlert.notify("Maintenance failed for #{@table&.fully_qualified_name}: #{@error_message}")
  end

  # The engine is NOT brought down per execution - that is the supervisor's
  # job, driven by demand. Only the per-table lock is freed here.
  def release_table_lock
    TableLock.release(@execution) if @scale_down
  end
end
