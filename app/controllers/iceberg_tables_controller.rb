# Manages the global view of iceberg tables across all catalogs: a filterable
# list and per-table detail (schedules, executions, freshness, health), plus a
# "run now" fallback. Each action authorizes with Pundit.
class IcebergTablesController < ApplicationController
  before_action :set_table, only: %i[show run_maintenance sync_table dismiss_errors]

  # Global view: every table of every catalog, with filters. With 100+
  # tables, browsing catalog by catalog does not scale.
  def index
    authorize IcebergTable
    @catalogs   = Catalog.order(:name)
    @namespaces = IcebergTable.distinct.order(:namespace).pluck(:namespace)
    @last_sync_at = IcebergTable.maximum(:metadata_synced_at)

    base = params[:inactive].present? ? IcebergTable.all : IcebergTable.active
    @tables = base.includes(:catalog, :maintenance_plan, :table_freshness_sla, :latest_freshness_check)

    @tables = @tables.where(catalog_id: params[:catalog_id])       if params[:catalog_id].present?
    @tables = @tables.where(namespace: params[:namespace])         if params[:namespace].present?
    @tables = @tables.where(health_status: params[:health_status]) if params[:health_status].present?

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
    @open_errors = ErrorEvent.open.table_events(@table).order(last_seen_at: :desc)
    @open_error_count = @open_errors.size
    # The banner names the dominant open error kind so the operator can decide
    # whether to follow the (table-scoped, kind-agnostic) History link.
    @open_error_groups = @open_errors.group_by(&:operation).transform_values(&:size)
    @executions = @table.execution_histories.latest.limit(20)
    @freshness_sla = @table.table_freshness_sla
    @freshness_checks = @table.freshness_checks.latest.limit(30)

    # READ the persisted evaluation; do not re-evaluate here. The score, the
    # status label and the breakdown are written together by the sync and by
    # the post-maintenance enrichment, so the list, the badge, the status
    # filter and this panel all describe the same evaluation. Recomputing on
    # read is what made the list and the detail disagree on both the score and
    # the label, and it came back every time HealthEvaluator changed (see #215,
    # after #165 and #198 each aligned one input).
    #
    # A table synced before the breakdown was persisted has no components yet;
    # evaluate once and persist, so the panel is populated from then on and
    # still only ever has one stored evaluation.
    @evaluation = @table.persisted_health_evaluation || backfill_health_evaluation(@table)
  end

  # Remembers that the operator dismissed the open-errors banner for this table
  # (session-scoped; a notice, not state).
  def dismiss_errors
    authorize @table
    session[:dismissed_error_banners] ||= []
    session[:dismissed_error_banners] << @table.id unless session[:dismissed_error_banners].include?(@table.id)
    redirect_to @table, notice: t("tables.banner_dismissed")
  end

  # Fallback for the table-level "run now": ensures a dispatchable plan exists
  # (creating a default one when the table has none, resuming it when paused)
  # and enqueues it. The operator clicked Run - that is intent to run, so a
  # paused plan is resumed rather than bounced back with an error. A table that
  # already has work queued or running is not enqueued again.
  def run_maintenance
    authorize @table, :run_maintenance?

    # A table with no addressable Trino identifier cannot be maintained, and
    # creating a default plan for it would raise. Say so instead.
    unless @table.addressable_in_trino?
      redirect_back fallback_location: iceberg_tables_path,
                    alert: t("tables.run_maintenance.not_addressable")
      return
    end

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

    MaintenanceOrchestrator.run_plan(plan.id, force: true)
    redirect_back fallback_location: iceberg_tables_path, notice: t("tables.run_maintenance.enqueued")
  end

  # Enqueues a metadata re-sync for every catalog so the table list reflects
  # the current state of the lake. Admin-only (touches every catalog).
  def sync_all
    authorize :catalog, :sync?
    Catalog.find_each { |catalog| MaintenanceOrchestrator.sync_catalog(catalog.id) }
    redirect_to iceberg_tables_path, notice: t("tables.index.sync_enqueued")
  end

  # Refreshes metadata for a single table without re-syncing the whole catalog.
  def sync_table
    authorize @table, :sync_table?
    CatalogSyncService.sync_table(@table.id)
    redirect_back fallback_location: iceberg_tables_path, notice: t("tables.sync_table.enqueued")
  end

  private

  # Evaluates and PERSISTS health for a table whose breakdown predates the
  # persisted column, then returns it in the read shape.
  #
  # This is a one-time backfill per table, not a read-path evaluation: it
  # writes, so the next render reads. Keeping it a write is what preserves the
  # single-evaluation invariant - a read that quietly evaluated its own value
  # is exactly the divergence #215 is about.
  #
  # @param table [IcebergTable] the table to backfill
  # @return [Hash] the evaluation in read shape
  def backfill_health_evaluation(table)
    extractor = TableMetadataExtractor.from_persisted(table)
    health = HealthEvaluator.evaluate(extractor, plan: table.maintenance_plan,
                                      manifest_count: table.manifest_count)
    attributes = table.health_attributes(health)
    table.update_columns(attributes) if attributes.any?

    table.persisted_health_evaluation || health
  end

  # Loads the iceberg table for the current request.
  def set_table
    @table = IcebergTable.find(params[:id])
  end
end
