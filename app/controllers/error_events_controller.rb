# Manages error events: a filterable list of operation failures plus bulk
# acknowledge and resolve actions. Each action authorizes with Pundit.
class ErrorEventsController < ApplicationController
  # Lists error events, filterable by operation, status, and catalog, capped
  # at the 200 most recent.
  def index
    authorize ErrorEvent
    scope = ErrorEvent.includes(:catalog).order(occurrence_count: :desc, last_seen_at: :desc)

    scope = scope.where(operation: params[:operation]) if params[:operation].present?
    scope = scope.where(status: params[:status]) if params[:status].in?(ErrorEvent::STATUSES)
    scope = scope.catalog_events(Catalog.find(params[:catalog_id])) if params[:catalog_id].present?
    @pagy, @events = pagy(scope)
  end

  # Marks the selected open error events as acknowledged in batches and
  # redirects back.
  def acknowledge
    authorize ErrorEvent
    params.fetch(:ids, []).each_slice(100) do |ids|
      ErrorEvent.where(id: ids, status: "open").update_all(status: "acknowledged", updated_at: Time.current)
    end
    redirect_back fallback_location: error_events_path,
                  notice: "#{Array(params[:ids]).size} error(s) acknowledged."
  end

  # Marks the selected open or acknowledged error events as resolved in
  # batches and redirects back.
  def resolve
    authorize ErrorEvent
    params.fetch(:ids, []).each_slice(100) do |ids|
      ErrorEvent.where(id: ids, status: %w[open acknowledged]).update_all(status: "resolved", updated_at: Time.current)
    end
    redirect_back fallback_location: error_events_path,
                  notice: "#{Array(params[:ids]).size} error(s) resolved."
  end
end
