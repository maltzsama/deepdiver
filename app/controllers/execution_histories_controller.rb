# Global log of operations. The per-table history stays in iceberg_tables#show;
# this screen answers "what happened recently" — maintenance executions and
# freshness checks interleaved chronologically in ONE merged list. The kind of
# event is a filter, not a tab: every filter only subtracts from the merged set.
class ExecutionHistoriesController < ApplicationController
  before_action :set_execution, only: %i[cancel]
  before_action :set_freshness_event, only: %i[acknowledge assign resolve]

  PAGE_SIZE = 50

  # Lists the merged timeline of executions and freshness checks, newest first.
  def index
    authorize ExecutionHistory
    @catalogs = Catalog.order(:name)
    timeline = OperationTimeline.new(
      kind: params[:kind],
      catalog_id: params[:catalog_id],
      status: params[:status],
      operation: params[:operation],
      stopped_at_step: params[:stopped_at_step]
    )

    page = params[:page].to_i.positive? ? params[:page].to_i : 1
    @pagy = Pagy::Offset.new(count: timeline.count, page: page, limit: PAGE_SIZE)
    @rows = timeline.rows(limit: PAGE_SIZE, offset: @pagy.offset)

    load_records(@rows)
    assignable_users # warm the memo for the triage select
  end

  # Operator cancellation of an execution: mark it failed (running) or skipped
  # (pending, never ran), free the table lock and let the supervisor decide
  # about the engine.
  def cancel
    authorize @execution, :cancel?
    status = @execution.status == "pending" ? :skipped : :failed
    @execution.update!(status: status, error_message: "cancelled by operator", finished_at: Time.current)
    TableLock.release(@execution)
    TrinoEngineSupervisor.demand_finished!
    redirect_to activity_path, notice: t("activity.notices.cancelled")
  end

  # Triage actions for freshness events, on the merged History list. Freshness
  # is the only assignable error class — a breached SLA is work for a person;
  # engine/catalog diagnostics are surfaced in context instead.
  def acknowledge
    authorize @event, :acknowledge?
    @event.acknowledge!(user: current_user)
    redirect_to execution_histories_path, notice: t("error_events.notices.acknowledged_one")
  end

  def assign
    authorize @event, :assign?
    target = assign_target
    return redirect_with_invalid_target unless target

    assignees = @event.assign_to!(target, by: current_user)
    notify_assignees(assignees)
    redirect_to execution_histories_path, notice: t("error_events.notices.assigned", count: assignees.size)
  rescue ArgumentError
    redirect_with_invalid_target
  end

  def resolve
    authorize @event, :resolve?
    @event.resolve!
    redirect_to execution_histories_path, notice: t("error_events.notices.resolved_one")
  end

  private

  # Loads the executions and checks referenced by the timeline rows, and the
  # freshness triage events for the checks, so the view renders without N+1.
  #
  # @param rows [Array<Hash>] the timeline rows
  def load_records(rows)
    execution_ids = rows.filter_map { |r| r[:record_id] if r[:kind] == "maintenance" }
    check_ids     = rows.filter_map { |r| r[:record_id] if r[:kind] == "freshness" }

    @executions = ExecutionHistory.where(id: execution_ids)
                                  .includes(iceberg_table: :catalog, execution_steps: :maintenance_step)
                                  .index_by(&:id)
    @checks = FreshnessCheck.where(id: check_ids)
                            .includes(iceberg_table: :catalog)
                            .index_by(&:id)
    @freshness_events = freshness_events_for(@checks.values)
  end

  # Loads the freshness event for triage actions.
  def set_freshness_event
    @event = ErrorEvent.find(params[:id])
  end

  # Resolves the assignment target from type/id form params.
  # @return [User, Team, nil]
  def assign_target
    case params[:target_type]
    when "user" then User.find_by(id: params[:target_id], role: %i[admin operator], status: "active")
    when "team" then Team.find_by(id: params[:target_id])
    end
  end

  # Flashes an error when the requested target does not exist or is not
  # assignable.
  def redirect_with_invalid_target
    redirect_to execution_histories_path, alert: t("error_events.notices.invalid_target")
  end

  # Emails every assignee; delivery problems never block the assignment.
  # @param assignees [Array<User>]
  def notify_assignees(assignees)
    assignees.each do |user|
      ErrorEventMailer.assignment_notification(to: user.email, event: @event, assigned_by: current_user)
                      .deliver_now
    rescue StandardError => e
      Rails.logger.warn("Assignment email to #{user.email} failed: #{e.message}")
    end
  end

  # Loads the execution for the current request.
  def set_execution
    @execution = ExecutionHistory.find(params[:id])
  end

  # The open/acknowledged freshness error events for the given checks, keyed by
  # (catalog_id, namespace, table) so the view can annotate each row's triage
  # state without N+1 queries.
  #
  # @param checks [Array<FreshnessCheck>] the checks on the page
  # @return [Hash{Array => ErrorEvent}] events keyed by [catalog_id, namespace, table]
  def freshness_events_for(checks)
    events = ErrorEvent.where(operation: ErrorEvent::FRESHNESS_OPERATION,
                              status: %w[open acknowledged])
    unless checks.empty?
      events = events.where(
        checks.map do |check|
          table = check.iceberg_table
          { catalog_id: table.catalog_id, schema: table.namespace, table: table.name }
        end
      )
    end

    events.index_by { |e| [ e.catalog_id, e.schema, e.table ] }
  end

  # The assignable users for a freshness triage action.
  # @return [Array<User>] active admins/operators ordered by email
  def assignable_users
    @assignable_users ||= User.active.where(role: %i[admin operator]).order(:email)
  end
end
