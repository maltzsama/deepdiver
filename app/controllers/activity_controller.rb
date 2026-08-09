# The "what is happening right now" screen: engine state, executions running,
# awaiting a commit-conflict retry, and queued.
class ActivityController < ApplicationController
  def show
    @engine_state = TrinoEngineSupervisor.state
    @running = ExecutionHistory.includes(:iceberg_table, :execution_steps, maintenance_plan: :maintenance_steps)
                               .where(status: "running")
                               .order(:created_at)
    @queued = ExecutionHistory.includes(:iceberg_table)
                              .where(status: "pending")
                              .order(:created_at)
  end

  def restart
    state = TrinoEngineSupervisor.state
    state.update!(status: "starting", start_attempts: 0, last_error: nil, status_changed_at: Time.current)
    MaintenanceOrchestrator.supervise_engine_start
    redirect_to activity_path, notice: "Engine start re-triggered."
  end
end
