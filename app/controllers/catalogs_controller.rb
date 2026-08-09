class CatalogsController < ApplicationController
  before_action :require_admin!, only: %i[new create edit update destroy sync verify]
  before_action :set_catalog, only: %i[show edit update destroy sync verify]

  def index
    @catalogs = Catalog.order(:name)
  end

  def show
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

  def edit; end

  def update
    if @catalog.update(catalog_params)
      redirect_to @catalog, notice: "Catalog updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @catalog.destroy
    redirect_to catalogs_path, notice: "Catalog deleted."
  end

  def sync
    MaintenanceOrchestrator.sync_catalog(@catalog.id)
    redirect_to @catalog, notice: "Catalog sync enqueued."
  end

  def verify
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

    # A blank secret means "keep the current one", not "delete it".
    creds = permitted[:catalog_credential_attributes]
    creds&.delete(:secret) if creds && creds[:secret].blank?

    permitted
  end
end
