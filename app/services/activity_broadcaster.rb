# Broadcasts updated partials to the /activity Turbo Stream channel so the
# page updates without a full reload. Called after every supervisor transition,
# maintenance step and freshness sweep boundary.
module ActivityBroadcaster
  module_function

  # Re-renders the /activity Turbo Stream channel: the engine strip, the
  # running/queued lists, the active queries, and the Solid Queue backlog, so
  # the page updates without a full reload.
  def broadcast!
    state = TrinoEngineSupervisor.state
    running = ExecutionHistory.includes(:iceberg_table, :execution_steps, maintenance_plan: :maintenance_steps)
                               .where(status: "running")
                               .order(:created_at)
    queued = ExecutionHistory.includes(:iceberg_table)
                              .where(status: "pending")
                              .order(:created_at)
    active_count = running.size + queued.size
    engine_events = ErrorEvent.where(source_system: "engine", operation: "engine-lifecycle")
                              .order(last_seen_at: :desc)
                              .limit(20)

    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-engine-strip",
      partial: "activity/engine_strip",
      locals: { engine_state: state, active_count: active_count }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-engine-history",
      partial: "activity/engine_history",
      locals: { engine_events: engine_events }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-running",
      partial: "activity/running",
      locals: { running: running, queued: queued, show_actions: false }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-queries",
      partial: "activity/queries",
      locals: { queries: TrinoProvisioner.active_queries, show_actions: false }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-queue",
      partial: "activity/queue",
      locals: { queue: QueueSummary.new.call, running: running, queued: queued }
    )
  end
end
