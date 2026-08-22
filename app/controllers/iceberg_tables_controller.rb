# Manages the global view of iceberg tables across all catalogs: a filterable
# list and per-table detail (schedules, executions, freshness, health), plus a
# "run now" fallback. Each action authorizes with Pundit.
class IcebergTablesController < ApplicationController
  before_action :set_table, only: %i[show run_maintenance]

  # Global view: every table of every catalog, with filters. With 100+
  # tables, browsing catalog by catalog does not scale.
  def index
    authorize IcebergTable
    @catalogs   = Catalog.order(:name)
    @namespaces = IcebergTable.distinct.order(:namespace).pluck(:namespace)
    @last_sync_at = IcebergTable.maximum(:metadata_synced_at)

    @tables = IcebergTable.active
                          .includes(:catalog, :maintenance_plan, :table_freshness_sla, :latest_freshness_check)

    @tables = @tables.where(catalog_id: params[:catalog_id])       if params[:catalog_id].present?
    @tables = @tables.where(namespace: params[:namespace])         if params[:namespace].present?
    @tables = @tables.where(health_status: params[:health_status]) if params[:health_status].present?

    if params[:inactive].present?
      @tables = IcebergTable.includes(:catalog, :maintenance_plan, :table_freshness_sla, :latest_freshness_check)
    end

    if params[:no_plan].present?
      @tables = @tables.where.not(id: MaintenancePlan.select(:iceberg_table_id))
    end

    if params[:freshness].present?
      case params[:freshness]
      when "late"    then @tables = @tables.where(id: TableFreshnessSla.where(status: "late").select(:iceberg_table_id))
      when "error"   then @tables = @tables.where(id: TableFreshnessSla.where(status: "error").select(:iceberg_table_id))
      when "no_sla"  then @tables = @tables.where.not(id: TableFreshnessSla.select(:iceberg_table_id))
      end
    end

    if params[:q].present?
      term = "%#{params[:q].downcase}%"
      @tables = @tables.where("LOWER(iceberg_tables.name) LIKE :t OR LOWER(iceberg_tables.namespace) LIKE :t", t: term)
    end

    @tables = @tables.order(Arel.sql("health_score ASC NULLS LAST"), :namespace, :name)

    @pagy, @tables = pagy(@tables)
  end

  # Shows one table with its open errors, schedules, recent executions,
  # freshness SLA/checks, and a health evaluation rebuilt from stored metadata.
  def show
    authorize @table
    @open_error_count = ErrorEvent.open.table_events(@table).count
    @executions = @table.execution_histories.latest.limit(20)
    @freshness_sla = @table.table_freshness_sla
    @freshness_checks = @table.freshness_checks.latest.limit(30)

    # Rebuilds the decomposition from the stored metadata (CR-42 columns) so the
    # score can explain itself without a new catalog round-trip.
    @extractor = TableMetadataExtractor.from_persisted(@table)
    @evaluation = HealthEvaluator.evaluate(@extractor, plan: @table.maintenance_plan)
  end

  # Fallback for the table-level "run now": ensures a dispatchable plan exists
  # (creating a default one when the table has none, resuming it when paused)
  # and enqueues it. The operator clicked Run - that is intent to run, so a
  # paused plan is resumed rather than bounced back with an error. A table that
  # already has work queued or running is not enqueued again.
  def run_maintenance
    authorize @table, :run_maintenance?
    plan = @table.maintenance_plan

    if plan.nil?
      plan = MaintenancePlan.create_default_for!(@table)
    elsif plan.paused?
      plan.update!(is_paused: false, consecutive_failures: 0, needs_review: false)
    end

    if plan.execution_histories.where(status: %w[pending running]).exists?
      redirect_back fallback_location: iceberg_tables_path, notice: t("tables.run_maintenance.already_queued")
      return
    end

    MaintenanceOrchestrator.run_plan(plan.id)
    redirect_back fallback_location: iceberg_tables_path, notice: t("tables.run_maintenance.enqueued")
  end

  # Enqueues a metadata re-sync for every catalog so the table list reflects
  # the current state of the lake. Admin-only (touches every catalog).
  def sync_all
    authorize :catalog, :sync?
    Catalog.find_each { |catalog| MaintenanceOrchestrator.sync_catalog(catalog.id) }
    redirect_to iceberg_tables_path, notice: t("tables.index.sync_enqueued")
  end

  private

  # Loads the iceberg table for the current request.
  def set_table
    @table = IcebergTable.find(params[:id])
  end
end
