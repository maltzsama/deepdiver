# Circuit breaker: marks an execution as failed, tracks consecutive failures on
# the schedule (pausing it after 3), alerts Slack, and always teardown the Trino
# engine by enqueueing the scale-down step.
class ExecutionFailureHandler
  MAX_CONSECUTIVE_FAILURES = 3

  def self.handle(execution, error_message, scale_down: true)
    new(execution, error_message, scale_down: scale_down).call
  end

  def initialize(execution, error_message, scale_down:)
    @execution = execution
    @error_message = error_message
    @scale_down = scale_down
    @schedule = execution.maintenance_schedule
  end

  def call
    fail_execution
    increment_and_maybe_pause
    notify
    ensure_trino_stopped

    @execution
  end

  private

  def fail_execution
    @execution.update!(status: :failed, error_message: @error_message)
  end

  def increment_and_maybe_pause
    @schedule.increment!(:consecutive_failures)

    return unless @schedule.consecutive_failures >= MAX_CONSECUTIVE_FAILURES

    @schedule.update!(is_paused: true)
    Rails.logger.warn("Schedule #{@schedule.id} paused after #{MAX_CONSECUTIVE_FAILURES} consecutive failures")
  end

  def notify
    SlackAlert.notify("Maintenance failed for schedule ##{@schedule.id} " \
                      "(#{@schedule.operation} on #{@schedule.iceberg_table.fully_qualified_name}): #{@error_message}")
  end

  def ensure_trino_stopped
    MaintenanceOrchestrator.scale_down(@execution.id) if @scale_down
  end
end
