# Read-only list of operation failures surfaced by the engine.
class ErrorEventsController < ApplicationController
  def index
    authorize ErrorEvent
    scope = ErrorEvent.includes(:catalog).order(occurrence_count: :desc, last_seen_at: :desc)

    scope = scope.where(operation: params[:operation]) if params[:operation].present?
    scope = scope.where(status: params[:status]) if params[:status].in?(ErrorEvent::STATUSES)
    scope = scope.catalog_events(Catalog.find(params[:catalog_id])) if params[:catalog_id].present?
    @pagy, @events = pagy(scope)
  end
end
