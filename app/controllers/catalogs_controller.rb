class CatalogsController < ApplicationController
  before_action :set_catalog, only: %i[show edit update destroy sync verify]

  def index
    authorize Catalog
    @catalogs = Catalog.order(:name)
  end

  def show
    authorize @catalog
    @open_error_count = ErrorEvent.open.catalog_events(@catalog).count
    @tables = @catalog.iceberg_tables
                  .left_joins(:maintenance_schedules)
                  .select("iceberg_tables.*, COUNT(maintenance_schedules.id) AS schedules_count")
                  .group("iceberg_tables.id")
                  .order(:namespace, :name)
  end

  def new
    authorize Catalog
    @catalog = Catalog.new
    @catalog.build_catalog_credential
  end

  def create
    authorize Catalog
    @catalog = Catalog.new(catalog_params)

    if @catalog.save
      redirect_to @catalog, notice: "Catalog created."
    else
      @catalog.build_catalog_credential if @catalog.catalog_credential.nil?
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @catalog
  end

  def update
    authorize @catalog
    if @catalog.update(catalog_params)
      redirect_to @catalog, notice: "Catalog updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @catalog
    @catalog.destroy
    redirect_to catalogs_path, notice: "Catalog deleted."
  end

  def sync
    authorize @catalog
    MaintenanceOrchestrator.sync_catalog(@catalog.id)
    redirect_to @catalog, notice: "Catalog sync enqueued."
  end

  def verify
    authorize @catalog
    result = @catalog.verify_connection!

    if result[:ok]
      redirect_to @catalog, notice: t("catalogs.verify.ok")
    else
      redirect_to @catalog, alert: t("catalogs.verify.failed", error: result[:error])
    end
  end

  private

  def set_catalog
    @catalog = Catalog.find(params[:id])
  end

  def catalog_params
    permitted = params.require(:catalog).permit(
      :name, :catalog_type, :endpoint, :trino_catalog_name_override,
      catalog_credential_attributes: %i[id auth_method client_id secret scope token_path]
    )

    creds = permitted[:catalog_credential_attributes]
    creds&.delete(:secret) if creds && creds[:secret].blank?

    permitted
  end
end
