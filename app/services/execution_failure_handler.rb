# Circuit breaker: marks an execution as failed, tracks consecutive failures on
# the maintenance plan (pausing it after the plan's threshold), alerts Slack,
# and frees the per-table lock. The engine lifecycle is the supervisor's job.
class ExecutionFailureHandler
  def self.handle(execution, error_message, scale_down: true)
    new(execution, error_message, scale_down: scale_down).call
  end

  def initialize(execution, error_message, scale_down:)
    @execution = execution
    @error_message = error_message
    @scale_down = scale_down
    @plan = execution.maintenance_plan
    @table = execution.iceberg_table
  end

  def call
    fail_execution
    increment_and_maybe_pause
    notify
    release_table_lock

    @execution
  end

  private

  def fail_execution
    @execution.update!(status: :failed, error_message: @error_message)
  end

  def increment_and_maybe_pause
    return if @plan.nil?

    @plan.increment!(:consecutive_failures)

    return unless @plan.consecutive_failures >= (@plan.auto_pause_after || 3)

    @plan.update!(is_paused: true)
    Rails.logger.warn("Plan #{@plan.id} paused after #{@plan.consecutive_failures} consecutive failures")
  end

  def notify
    SlackAlert.notify("Maintenance failed for #{@table&.fully_qualified_name}: #{@error_message}")
  end

  # The engine is NOT brought down per execution - that is the supervisor's
  # job, driven by demand. Only the per-table lock is freed here.
  def release_table_lock
    TableLock.release(@execution) if @scale_down
  end
end
