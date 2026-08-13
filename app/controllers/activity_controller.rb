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
    redirect_to activity_path, notice: "Engine start re-triggered."
  end
end
