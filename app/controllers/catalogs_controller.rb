class CatalogsController < ApplicationController
  before_action :require_admin!, only: %i[new create destroy sync]

  def index
    @catalogs = Catalog.order(:name)
  end

  def show
    @catalog = Catalog.find(params[:id])
    @tables = @catalog.iceberg_tables
                  .left_joins(:maintenance_schedules)
                  .select("iceberg_tables.*, COUNT(maintenance_schedules.id) AS schedules_count")
                  .group("iceberg_tables.id")
                  .order(:namespace, :name)
  end

  def new
    @catalog = Catalog.new
  end

  def create
    @catalog = Catalog.new(catalog_params)

    if @catalog.save
      redirect_to @catalog, notice: "Catalog created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @catalog = Catalog.find(params[:id])
    @catalog.destroy
    redirect_to catalogs_path, notice: "Catalog deleted."
  end

  def sync
    @catalog = Catalog.find(params[:id])
    MaintenanceOrchestrator.sync_catalog(@catalog.id)
    redirect_to @catalog, notice: "Catalog sync enqueued."
  end

  private

  def catalog_params
    params.require(:catalog).permit(:name, :catalog_type, :endpoint, :trino_catalog_name, :properties).tap do |permitted|
      if permitted[:properties].is_a?(String)
        permitted[:properties] = JSON.parse(permitted[:properties])
      end
    rescue JSON::ParserError
      # leave the raw string; the catalog validations guard the rest
    end
  end
end
