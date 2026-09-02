# Merged, chronologically-interleaved timeline of maintenance executions and
# freshness checks — the "what happened recently" view. One list, no tabs: the
# kind of event is a filter, not a navigation control.
#
# The two record types have no common parent, so the merge is a SQL UNION over
# a shared shape (kind, record_id, iceberg_table_id, occurred_at, status),
# paginated on the shared ordering column — no per-type pagination, no tail cut.
class OperationTimeline
  KINDS = %w[maintenance freshness].freeze

  # Creates the timeline query with the active filters.
  #
  # @param kind [String, nil] restrict to one kind ("maintenance"/"freshness")
  # @param catalog_id [Integer, nil] restrict to one catalog
  # @param status [String, nil] restrict by status (applied per kind)
  # @param operation [String, nil] maintenance-only: executions containing this step
  # @param stopped_at_step [String, nil] maintenance-only: executions failed at this step
  def initialize(kind: nil, catalog_id: nil, table_id: nil, status: nil, operation: nil, stopped_at_step: nil)
    @kind = kind
    @catalog_id = catalog_id
    @table_id = table_id
    @status = status
    @operation = operation
    @stopped_at_step = stopped_at_step
  end

  # The total number of rows across the merged set, for pagination.
  #
  # @return [Integer] the row count
  def count
    sql = <<~SQL
      SELECT COUNT(*) AS n FROM (
        #{union_sql}
      ) AS timeline
    SQL
    execute(sql).first["n"].to_i
  end

  # A paginable collection exposing the Pagy helper's expected interface
  # (count, offset, limit). Using the official `pagy` helper keeps the pager
  # on the framework's own (Brakeman-recognised) path instead of a hand-built
  # Pagy::Offset carrying request parameters.
  #
  # @return [OperationTimeline::Collection] the paginable wrapper
  def collection
    Collection.new(self)
  end

  # The rows for one page, newest first, each a hash of the shared shape.
  #
  # @param limit [Integer] the page size
  # @param offset [Integer] the page offset
  # @return [Array<Hash>] { "kind", "record_id", "iceberg_table_id", "occurred_at", "status" }
  def rows(limit:, offset:)
    sql = <<~SQL
      SELECT kind, record_id, iceberg_table_id, occurred_at, status, created_at
      FROM (
        #{union_sql}
      ) AS timeline
      ORDER BY occurred_at DESC
      LIMIT #{limit.to_i} OFFSET #{offset.to_i}
    SQL
    execute(sql).map { |row| row.symbolize_keys }
  end

  private

  # The two SELECTs, one per kind, UNIONed. Each branch applies its own status
  # filter (the status vocabularies differ) while kind/catalog/operation filters
  # are shared.
  #
  # @return [String] the UNION ALL SQL
  def union_sql
    branches = []
    branches << maintenance_select if kind_includes?("maintenance")
    branches << freshness_select if kind_includes?("freshness")
    branches.join(" UNION ALL ")
  end

  # Whether the kind filter includes a given kind.
  #
  # @param kind [String] "maintenance" or "freshness"
  # @return [Boolean]
  def kind_includes?(kind)
    @kind.nil? || @kind == kind
  end

  # The maintenance branch: executions with their rich detail intact.
  #
  # @return [String] the SELECT SQL
  def maintenance_select
    <<~SQL
      SELECT
        'maintenance' AS kind,
        e.id AS record_id,
        e.iceberg_table_id,
        COALESCE(e.started_at, e.created_at) AS occurred_at,
        e.status AS status,
        e.created_at
      FROM execution_histories e
      #{joins_for_maintenance}
      #{where_for_maintenance}
    SQL
  end

  # The freshness branch: checks, whose triage state is derived from the
  # matching ErrorEvent at render time.
  #
  # @return [String] the SELECT SQL
  def freshness_select
    <<~SQL
      SELECT
        'freshness' AS kind,
        f.id AS record_id,
        f.iceberg_table_id,
        f.checked_at AS occurred_at,
        f.status AS status,
        f.created_at
      FROM freshness_checks f
      #{where_for_freshness}
    SQL
  end

  # JOINs needed for the maintenance-only filters (operation / stopped_at_step).
  #
  # @return [String] the JOIN SQL
  def joins_for_maintenance
    sql = +""
    if @operation.present? || @stopped_at_step.present?
      sql << "JOIN execution_steps es ON es.execution_history_id = e.id"
    end
    sql
  end

  # The maintenance WHERE clause: table, catalog, status, operation, stopped-at-step.
  #
  # @return [String] the WHERE SQL
  def where_for_maintenance
    conds = []
    conds << "e.iceberg_table_id = #{@table_id.to_i}" if @table_id.present?
    conds << "e.iceberg_table_id IN (SELECT id FROM iceberg_tables WHERE catalog_id = #{@catalog_id.to_i})" if @catalog_id.present?
    conds << "e.status = #{quote(@status)}" if @status.present?
    if @operation.present?
      conds << "e.id IN (SELECT execution_history_id FROM execution_steps WHERE operation = #{quote(@operation)})"
    end
    if @stopped_at_step.present?
      conds << "e.id IN (SELECT execution_history_id FROM execution_steps WHERE operation = #{quote(@stopped_at_step)} AND status = 'failed')"
    end
    conds.empty? ? "" : "WHERE #{conds.join(" AND ")}"
  end

  # The freshness WHERE clause: table, catalog and status.
  #
  # @return [String] the WHERE SQL
  def where_for_freshness
    conds = []
    conds << "f.iceberg_table_id = #{@table_id.to_i}" if @table_id.present?
    conds << "f.iceberg_table_id IN (SELECT id FROM iceberg_tables WHERE catalog_id = #{@catalog_id.to_i})" if @catalog_id.present?
    conds << "f.status = #{quote(@status)}" if @status.present?
    conds.empty? ? "" : "WHERE #{conds.join(" AND ")}"
  end

  # Quotes a value for raw SQL, or returns "NULL" for nil.
  #
  # @param value [Object, nil] the value to quote
  # @return [String] the SQL literal
  def quote(value)
    return "NULL" if value.nil?

    ActiveRecord::Base.connection.quote(value)
  end

  # Executes raw SQL.
  #
  # @param sql [String] the SQL statement
  # @return [Array<Hash>] the result rows
  def execute(sql)
    ActiveRecord::Base.connection.select_all(sql).to_a
  end

  # Adapter between the timeline and Pagy's `pagy` helper. Pagy calls `count`
  # then `offset(n).limit(n)`; we return the already-paginated rows from the
  # UNION query.
  class Collection
    # Creates the adapter for a timeline.
    #
    # @param timeline [OperationTimeline] the query to paginate
    def initialize(timeline)
      @timeline = timeline
    end

    # @return [Integer] the merged row count
    def count
      @timeline.count
    end

    # Returns self with a pending offset (Pagy chains offset → limit).
    #
    # @param offset [Integer] the page offset
    # @return [OperationTimeline::Collection] self
    def offset(offset)
      @offset = offset
      self
    end

    # Fetches the page rows.
    #
    # @param limit [Integer] the page size
    # @return [Array<Hash>] the paginated rows
    def limit(limit)
      @timeline.rows(limit: limit, offset: @offset.to_i)
    end
  end
end
