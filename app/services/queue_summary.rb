# Read-only snapshot of the Solid Queue worker queues for the activity screen.
# The queue lives in its own database (production only); in dev/test the tables
# do not exist, so every access degrades to empty instead of raising.
class QueueSummary
  # Builds the summary, tolerating a missing or unreachable queue database.
  def call
    {
      ready: SolidQueue::ReadyExecution.count,
      scheduled: SolidQueue::ScheduledExecution.count,
      running: SolidQueue::ClaimedExecution.count,
      failed: SolidQueue::FailedExecution.count,
      processes: SolidQueue::Process.count,
      next_jobs: next_jobs
    }
  rescue StandardError
    { ready: 0, scheduled: 0, running: 0, failed: 0, processes: 0, next_jobs: [] }
  end

  private

  # The next few ready jobs, most urgent first.
  #
  # @return [Array<Hash>] a compact job descriptor
  def next_jobs
    SolidQueue::ReadyExecution.ordered.limit(10).map do |ready|
      job = ready.job
      {
        id: job.id,
        class_name: job.class_name,
        queue_name: ready.queue_name,
        scheduled_at: ready.created_at
      }
    end
  rescue StandardError
    []
  end
end
