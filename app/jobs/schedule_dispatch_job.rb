class ScheduleDispatchJob < ApplicationJob
  queue_as :maintenance

  # The heavyweight twin of the catalog recurring sync: checks every active,
  # non-paused schedule against the current minute and enqueues a run when its
  # cron matches. Runs every minute in production.
  def perform
    MaintenanceSchedule.dispatchable.find_each do |schedule|
      next unless schedule.scheduled_at?

      MaintenanceOrchestrator.run_schedule(schedule.id)
    end
  rescue StandardError => e
    Rails.logger.error("ScheduleDispatchJob failed: #{e.message}")
  end
end
