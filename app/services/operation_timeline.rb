# Chronological log of maintenance executions — the "what happened recently"
# view. The per-table history stays in iceberg_tables#show.
class OperationTimeline
  # Creates the timeline query with the active filters.
  #
  # @param catalog_id [Integer, nil] restrict to one catalog
  # @param status [String, nil] restrict by status
  # @param operation [String, nil] executions containing this step
  # @param stopped_at_step [String, nil] executions failed at this step
  def initialize(catalog_id: nil, table_id: nil, status: nil, operation: nil, stopped_at_step: nil)
    @catalog_id = catalog_id
    @table_id = table_id
    @status = status
    @operation = operation
    @stopped_at_step = stopped_at_step
  end

  # The total number of rows, for pagination.
  #
  # @return [Integer] the row count
  def count
    sql = <<~SQL
      SELECT COUNT(*) AS n FROM (
        #{timeline_sql}
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
        #{timeline_sql}
      ) AS timeline
      ORDER BY occurred_at DESC
      LIMIT #{limit.to_i} OFFSET #{offset.to_i}
    SQL
    execute(sql).map { |row| row.symbolize_keys }
  end

  private

  # The executions with their rich detail intact.
  #
  # @return [String] the SELECT SQL
  def timeline_sql
    <<~SQL
      SELECT
        'maintenance' AS kind,
        e.id AS record_id,
        e.iceberg_table_id,
        COALESCE(e.started_at, e.created_at) AS occurred_at,
        e.status AS status,
        e.created_at
      FROM execution_histories e
      #{joins}
      #{where_clause}
    SQL
  end

  # JOINs needed for the maintenance-only filters (operation / stopped_at_step).
  #
  # @return [String] the JOIN SQL
  def joins
    sql = +""
    if @operation.present? || @stopped_at_step.present?
      sql << "JOIN execution_steps es ON es.execution_history_id = e.id"
    end
    sql
  end

  # The WHERE clause: table, catalog, status, operation, stopped-at-step.
  #
  # @return [String] the WHERE SQL
  def where_clause
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
  # query.
  class Collection
    # Creates the adapter for a timeline.
    #
    # @param timeline [OperationTimeline] the query to paginate
    def initialize(timeline)
      @timeline = timeline
    end

    # @return [Integer] the row count
    def count
      @timeline.count
    end

    # Returns self with a pending offset (Pagy chains offset → limit).
    #
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
