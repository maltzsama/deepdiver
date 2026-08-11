# Broadcasts updated partials to the /activity Turbo Stream channel so the
# page updates without a full reload. Called after every supervisor transition,
# maintenance step and freshness sweep boundary.
module ActivityBroadcaster
  module_function

  # Re-renders the /activity Turbo Stream channel: the engine strip and the
  # running/queued lists, so the page updates without a full reload.
  def broadcast!
    state = TrinoEngineSupervisor.state
    running = ExecutionHistory.includes(:iceberg_table, :execution_steps, maintenance_plan: :maintenance_steps)
                               .where(status: "running")
                               .order(:created_at)
    queued = ExecutionHistory.includes(:iceberg_table)
                              .where(status: "pending")
                              .order(:created_at)
    active_count = running.size + queued.size

    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-engine-strip",
      partial: "activity/engine_strip",
      locals: { engine_state: state, active_count: active_count }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-running",
      partial: "activity/running",
      locals: { running: running, queued: queued, show_actions: false }
    )
  end
end
