# Manages catalogs: the external systems whose iceberg tables are tracked.
# Provides the usual CRUD plus sync (re-scan metadata) and verify (test the
# connection). Every action authorizes with Pundit.
class CatalogsController < ApplicationController
  before_action :set_catalog, only: %i[show edit update destroy sync verify]

  # Lists all catalogs ordered by name.
  def index
    authorize Catalog
    @catalogs = Catalog.order(:name)
  end

  # Shows a catalog with its open error count and tables. Active tables by
  # default; the operator can include inactive ones.
  def show
    authorize @catalog
    @open_error_count = ErrorEvent.open.catalog_events(@catalog).count
    tables = @catalog.iceberg_tables
    tables = tables.active unless params[:inactive].present?
    @tables = tables.order(:namespace, :name)
  end

  # Renders the form for creating a catalog, with a fresh credential object.
  def new
    authorize Catalog
    @catalog = Catalog.new
    @catalog.build_catalog_credential
  end

  # Creates a catalog and redirects to it, or re-renders the form on failure.
  def create
    authorize Catalog
    @catalog = Catalog.new(catalog_params)

    if @catalog.save
      redirect_to @catalog, notice: t("catalogs.notices.created")
    else
      @catalog.build_catalog_credential if @catalog.catalog_credential.nil?
      render :new, status: :unprocessable_content
    end
  end

  # Renders the edit form for a catalog.
  def edit
    authorize @catalog
  end

  # Updates the catalog and redirects to it, or re-renders the form on failure.
  def update
    authorize @catalog
    if @catalog.update(catalog_params)
      redirect_to @catalog, notice: t("catalogs.notices.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Destroys the catalog and redirects to the catalogs index.
  def destroy
    authorize @catalog
    @catalog.destroy
    redirect_to catalogs_path, notice: t("catalogs.notices.destroyed")
  end

  # Enqueues a metadata re-sync for the catalog and redirects to it.
  def sync
    authorize @catalog
    MaintenanceOrchestrator.sync_catalog(@catalog.id)
    redirect_to @catalog, notice: t("catalogs.notices.sync_enqueued")
  end

  # Verifies the catalog connection and redirects with the outcome as notice
  # or alert.
  def verify
    authorize @catalog
    result = @catalog.verify_connection!

    if result[:ok]
      redirect_to @catalog, notice: t("catalogs.verify.ok", count: result[:namespace_count])
    else
      redirect_to @catalog, alert: t("catalogs.verify.failed", error: result[:error])
    end
  end

  # Tests a catalog connection from form params without persisting. Used by
  # the new/edit form "Test connection" button.
  def verify_draft
    authorize Catalog
    catalog = Catalog.new(catalog_params)
    catalog.build_catalog_credential(catalog_params[:catalog_credential_attributes]) if catalog_params[:catalog_credential_attributes]
    result = catalog.verify_connection!

    if result[:ok]
      redirect_back fallback_location: catalogs_path, notice: t("catalogs.verify.ok", count: result[:namespace_count])
    else
      redirect_back fallback_location: catalogs_path, alert: t("catalogs.verify.failed", error: result[:error])
    end
  end

  private

  # Loads the catalog for the current request.
  def set_catalog
    @catalog = Catalog.find(params[:id])
  end

  # Strong parameters for a catalog, including nested credential attributes.
  # A blank secret means "keep the stored one", never "erase it" - erasing is
  # an explicit edit to a placeholder sentinel handled by the model contract.
  def catalog_params
    permitted = params.require(:catalog).permit(
      :name, :catalog_type, :endpoint, :trino_catalog_name_override, :nessie_ref,
      :nessie_api_mode, :nessie_warehouse,
      :s3_authentication_type, :s3_endpoint, :s3_access_key, :s3_secret_key,
      :s3_role_arn, :s3_external_id, :s3_region,
      catalog_credential_attributes: [
        :id, :auth_method, :client_id, :secret, :scope, :token_path,
        :token_endpoint, :oauth_scope, { properties: {} }
      ]
    )

    creds = permitted[:catalog_credential_attributes]
    creds&.delete(:secret) if creds && creds[:secret].blank?

    # Blank s3_secret_key means "keep the stored one", same pattern as catalog_credential.
    permitted.delete(:s3_secret_key) if permitted[:s3_secret_key].blank?

    permitted
  end
end
