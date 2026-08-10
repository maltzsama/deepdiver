class ErrorEventsController < ApplicationController
  def index
    authorize ErrorEvent
    scope = ErrorEvent.order(occurrence_count: :desc, last_seen_at: :desc)

    scope = scope.where(operation: params[:operation]) if params[:operation].present?
    scope = scope.where(status: params[:status]) if params[:status].in?(ErrorEvent::STATUSES)
    scope = scope.catalog_events(Catalog.find(params[:catalog_id])) if params[:catalog_id].present?

    @events = scope.limit(200)
    @open_count = ErrorEvent.open.count
  end

  def acknowledge
    authorize ErrorEvent
    params.fetch(:ids, []).each_slice(100) do |ids|
      ErrorEvent.where(id: ids, status: "open").update_all(status: "acknowledged", updated_at: Time.current)
    end
    redirect_back fallback_location: error_events_path,
                  notice: "#{Array(params[:ids]).size} error(s) acknowledged."
  end

  def resolve
    authorize ErrorEvent
    params.fetch(:ids, []).each_slice(100) do |ids|
      ErrorEvent.where(id: ids, status: %w[open acknowledged]).update_all(status: "resolved", updated_at: Time.current)
    end
    redirect_back fallback_location: error_events_path,
                  notice: "#{Array(params[:ids]).size} error(s) resolved."
  end
end
