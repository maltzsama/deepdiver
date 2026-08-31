# Error event surface: a filterable list of failures plus the detail screen
# where admins/operators assign, acknowledge and resolve them.
class ErrorEventsController < ApplicationController
  before_action :set_event, only: %i[show acknowledge assign resolve]

  # Lists error events, filterable by operation, status, and catalog.
  def index
    authorize ErrorEvent
    scope = ErrorEvent.includes(:catalog).not_lifecycle.order(occurrence_count: :desc, last_seen_at: :desc)

    scope = scope.where(operation: params[:operation]) if params[:operation].present?
    scope = scope.where(status: params[:status]) if params[:status].in?(ErrorEvent::STATUSES)
    scope = scope.catalog_events(Catalog.find(params[:catalog_id])) if params[:catalog_id].present?
    @pagy, @events = pagy(scope)
    @operations = ErrorEvent.not_lifecycle.distinct.pluck(:operation).sort
    @status_counts = ErrorEvent.not_lifecycle.group(:status).count
  end

  # Full detail of one failure: message, context, assignment state.
  def show
    authorize @event
    @assignable_users = User.active.where(role: %i[admin operator]).order(:email)
    @teams = Team.order(:name)
  end

  # The assignee (or an admin) takes ownership of the problem.
  def acknowledge
    authorize @event
    @event.acknowledge!(user: current_user)
    redirect_to error_event_path(@event), notice: t("error_events.notices.acknowledged_one")
  end

  # Assigns to a user or team and notifies every assignee by email.
  def assign
    authorize @event
    target = assign_target
    return redirect_with_invalid_target unless target

    assignees = @event.assign_to!(target, by: current_user)
    notify_assignees(assignees)
    redirect_to error_event_path(@event), notice: t("error_events.notices.assigned", count: assignees.size)
  rescue ArgumentError
    redirect_with_invalid_target
  end

  # Closes the event as fixed.
  def resolve
    authorize @event
    @event.resolve!
    redirect_to error_event_path(@event), notice: t("error_events.notices.resolved_one")
  end

  private

  # Finds the event for member actions.
  def set_event
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
    redirect_to error_event_path(@event), alert: t("error_events.notices.invalid_target")
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
end
