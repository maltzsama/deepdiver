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
    plan_ids = running.map(&:maintenance_plan_id).compact.uniq
    typical_durations = MaintenancePlan.typical_durations_for(plan_ids)
    queries = TrinoProvisioner.safe_active_queries
    active_count = running.size + queued.size
    engine_events = ErrorEvent.where(source_system: "engine", operation: "engine-lifecycle")
                              .order(last_seen_at: :desc)
                              .limit(20)
    # Read idleness from the tables directly, never through TrinoDemand: its
    # #count calls reap_orphans!, which would fail executions from a broadcast.
    engine_idle = state.status == "down" && running.empty? && queued.empty? &&
                  !FreshnessRun.where(status: %w[pending running]).exists?

    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-engine-strip",
      partial: "activity/engine_strip",
      locals: { engine_state: state, active_count: active_count, queries: queries.size,
                engine_timer: true, engine_events: engine_events, engine_idle: engine_idle }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-engine-history",
      partial: "activity/engine_history",
      locals: { engine_events: engine_events }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-in-progress",
      partial: "activity/in_progress",
      locals: { running: running, queued: queued, queries: queries, typical_durations: typical_durations, show_actions: false }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "activity",
      target: "activity-queue",
      partial: "activity/queue",
      locals: { queue: QueueSummary.new.call, running: running, queued: queued }
    )
  rescue StandardError => e
    Rails.logger.warn("ActivityBroadcaster failed: #{e.class}: #{e.message}")
  end
end
