# Dispatches maintenance runs by checking every active, non-paused plan against
# the current minute and enqueuing a run when its cron schedule matches.
class ScheduleDispatchJob < ApplicationJob
  # On its OWN queue: the maintenance queue is single-threaded and shared with
  # ExecuteMaintenanceJob, whose long SQL steps would block this every-minute
  # dispatcher for their entire duration — dropping every cron occurrence that
  # fell inside the window (plans do not run late, they do not run at all).
  queue_as :dispatch

  # The heavyweight twin of the catalog recurring sync: checks every active,
  # non-paused maintenance plan against the current minute and enqueues a run
  # when its cron matches. Runs every minute in production.
  def perform
    MaintenancePlan.dispatchable.joins(:iceberg_table)
                   .where(iceberg_tables: { active: true })
                   .find_each do |plan|
      begin
        next unless plan.scheduled_at?

        MaintenanceOrchestrator.run_plan(plan.id)
      rescue StandardError => e
        Rails.logger.error("ScheduleDispatchJob failed for plan #{plan.id}: #{e.message}")
      end
    end
  end
end
