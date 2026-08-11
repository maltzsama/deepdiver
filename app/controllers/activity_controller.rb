# The "what is happening right now" screen: engine state, executions running,
# awaiting a commit-conflict retry, and queued.
class ActivityController < ApplicationController
  # Shows the live engine state, running executions, and queued executions.
  def show
    authorize :activity, :show?
    @engine_state = TrinoEngineSupervisor.state
    @running = ExecutionHistory.includes(:iceberg_table, :execution_steps, maintenance_plan: :maintenance_steps)
                               .where(status: "running")
                               .order(:created_at)
    @queued = ExecutionHistory.includes(:iceberg_table)
                              .where(status: "pending")
                              .order(:created_at)
  end

  # Re-triggers the engine start through the supervisor and redirects back to
  # the activity screen.
  def restart
    authorize :activity, :restart?
    TrinoEngineSupervisor.restart!
    redirect_to activity_path, notice: "Engine start re-triggered."
  end
end
