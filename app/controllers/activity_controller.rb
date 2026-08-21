# The "what is happening right now" screen: engine state, executions running,
# awaiting a commit-conflict retry, and queued.
class ActivityController < ApplicationController
  # Shows the live engine state, running executions, queued executions, active
  # Trino queries, the Solid Queue backlog, and the recent engine lifecycle.
  def show
    authorize :activity, :show?
    @engine_state = TrinoEngineSupervisor.state
    @running = ExecutionHistory.includes(:iceberg_table, :execution_steps, maintenance_plan: :maintenance_steps)
                               .where(status: "running")
                               .order(:created_at)
    @queued = ExecutionHistory.includes(:iceberg_table)
                              .where(status: "pending")
                              .order(:created_at)
    @queries = TrinoProvisioner.active_queries
    @queue = QueueSummary.new.call
    @engine_events = ErrorEvent.where(source_system: "engine", operation: "engine-lifecycle")
                               .order(last_seen_at: :desc)
                               .limit(20)
  end

  # Re-triggers the engine start through the supervisor and redirects back to
  # the activity screen.
  def restart
    authorize :activity, :restart?
    TrinoEngineSupervisor.restart!
    redirect_to activity_path, notice: t("activity.notices.restart")
  end

  # Forcibly tears down a frozen engine: fails in-flight work, clears the queue,
  # and scales the Trino cluster down. Redirects back to the activity screen.
  def hard_reset
    authorize :activity, :hard_reset?
    TrinoEngineSupervisor.hard_reset!
    redirect_to activity_path, notice: t("activity.notices.hard_reset")
  end

  # Cancels a running or queued Trino query on the coordinator.
  def cancel_query
    authorize :activity, :cancel_query?
    TrinoProvisioner.cancel_query(params[:query_id])
    ActivityBroadcaster.broadcast!
    redirect_to activity_path, notice: t("activity.notices.query_cancelled")
  end
end
