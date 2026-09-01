# Global log of operations. The per-table history stays in iceberg_tables#show;
# this screen answers "what ran on the lake today". Maintenance and freshness
# are separate tabs with separate schemas - never interleaved, each paginated
# on its own source (the old merge of two limit(200) dropped the tail).
class ExecutionHistoriesController < ApplicationController
  before_action :set_execution, only: %i[cancel]
  before_action :set_freshness_event, only: %i[acknowledge assign resolve]

  TABS = %w[maintenance freshness].freeze

  # Lists executions as one block per run (timeline bar + legend) for the
  # maintenance tab, or a simple scan list for the freshness tab.
  def index
    authorize ExecutionHistory
    @catalogs = Catalog.order(:name)
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "maintenance"

    if @tab == "freshness"
      @pagy, @checks = pagy(freshness_scope, limit: 50)
      @freshness_events = freshness_events_for(@checks)
    else
      @pagy, @executions = pagy(maintenance_scope, limit: 50)
    end
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

  # Triage actions for freshness events, on the History freshness tab. These
  # are the only assignable error class — a breached freshness SLA is work for
  # a person; engine/catalog diagnostics are surfaced in context instead.
  def acknowledge
    authorize @event, :acknowledge?
    @event.acknowledge!(user: current_user)
    redirect_to execution_histories_path(tab: "freshness"), notice: t("error_events.notices.acknowledged_one")
  end

  def assign
    authorize @event, :assign?
    target = assign_target
    return redirect_with_invalid_target unless target

    assignees = @event.assign_to!(target, by: current_user)
    notify_assignees(assignees)
    redirect_to execution_histories_path(tab: "freshness"), notice: t("error_events.notices.assigned", count: assignees.size)
  rescue ArgumentError
    redirect_with_invalid_target
  end

  def resolve
    authorize @event, :resolve?
    @event.resolve!
    redirect_to execution_histories_path(tab: "freshness"), notice: t("error_events.notices.resolved_one")
  end

  private

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
    redirect_to execution_histories_path(tab: "freshness"), alert: t("error_events.notices.invalid_target")
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

  # Maintenance executions with catalog/status/operation/stopped-at filters.
  def maintenance_scope
    scope = ExecutionHistory.includes(iceberg_table: :catalog, execution_steps: :maintenance_step)
    scope = scope.joins(:iceberg_table).where(iceberg_tables: { catalog_id: params[:catalog_id] }) if params[:catalog_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    if params[:operation].present?
      scope = scope.where(id: ExecutionHistory.joins(:execution_steps)
                        .where(execution_steps: { operation: params[:operation] }).select(:id))
    end
    if params[:stopped_at_step].present?
      scope = scope.where(id: ExecutionHistory.joins(:execution_steps)
                        .where(execution_steps: { operation: params[:stopped_at_step], status: "failed" }).select(:id))
    end

    scope.latest
  end

  # Freshness scans with catalog filter; the status filter speaks maintenance,
  # so map it onto the closest freshness meaning.
  def freshness_scope
    scope = FreshnessCheck.includes(iceberg_table: :catalog)
    scope = scope.joins(:iceberg_table).where(iceberg_tables: { catalog_id: params[:catalog_id] }) if params[:catalog_id].present?
    scope = scope.where(status: freshness_status_filter) if params[:status].present?

    scope.latest
  end

  # The open/acknowledged freshness error events for the tables in the current
  # page, keyed by (catalog_id, namespace, table) so the view can annotate each
  # check's row with its triage state without N+1 queries.
  #
  # @param checks [ActiveRecord::Relation] the freshness checks on the page
  # @return [Hash{Array => ErrorEvent}] events keyed by [catalog_id, namespace, table]
  def freshness_events_for(checks)
    events = ErrorEvent.where(operation: ErrorEvent::FRESHNESS_OPERATION,
                              status: %w[open acknowledged])
    events = events.where(
      checks.map do |check|
        table = check.iceberg_table
        { catalog_id: table.catalog_id, schema: table.namespace, table: table.name }
      end
    ) unless checks.empty?

    events.index_by { |e| [ e.catalog_id, e.schema, e.table ] }
  end

  # The assignable users for a freshness triage action.
  # @return [Array<User>] active admins/operators ordered by email
  def assignable_users
    @assignable_users ||= User.active.where(role: %i[admin operator]).order(:email)
  end

  # Maps maintenance statuses onto freshness ones ("failed"->"error").
  def freshness_status_filter
    { "failed" => "error", "success" => "ok" }.fetch(params[:status], params[:status])
  end
end
