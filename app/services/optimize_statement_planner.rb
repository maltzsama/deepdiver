# Plans OPTIMIZE as one statement per bounded group of partitions, so no single
# query ever opens more writers than Trino's Iceberg connector default
# (iceberg.max-partitions-per-writer = 100) allows.
#
# A table that is badly behind on maintenance can accumulate far more identity
# partitions than any static limit - a table that missed 100 daily partitions
# could just as easily miss 1000. Batching sidesteps the ceiling entirely:
# each statement touches only a bounded subset of the partition column, so it
# always completes instead of failing outright on the tables that need the
# maintenance most.
#
# Batching only applies when it is safe to scope by partition:
#   * the step is an OPTIMIZE
#   * the operator did not already set a WHERE predicate (that would conflict)
#   * the table has a single identity-transformed partition column
# In every other case the planner returns the single, unbatched statement, so
# behaviour is unchanged.
class OptimizeStatementPlanner
  # Safety margin below the connector default of 100 writers. Overridable per
  # step via config["partitions_per_query"].
  DEFAULT_PARTITIONS_PER_QUERY = 80

  # Creates the planner for a table and step.
  #
  # @param table [IcebergTable] the target table
  # @param step [MaintenanceStep] the step describing the operation
  # @param runtime [Object] the Trino runtime used to discover partition values
  def initialize(table, step, runtime: TrinoRuntime)
    @table = table
    @step = step
    @runtime = runtime
  end

  # The OPTIMIZE statements to run for this table/step, in order.
  #
  # @param execution_id [Integer] the execution id for header tagging
  # @return [Array<String>] one or more ALTER TABLE ... EXECUTE statements
  def statements(execution_id:)
    return [ single_statement ] unless batchable?

    partition_column = identity_partition_column
    values = distinct_partition_values(partition_column, execution_id)
    return [ single_statement ] if values.empty?

    chunks = values.each_slice(partitions_per_query).to_a
    chunks.map do |chunk|
      MaintenanceSqlBuilder.build(@table, @step, where: "#{quote_ident(partition_column)} IN (#{chunk.map { |v| sql_literal(v) }.join(", ")})")
    end
  end

  private

  # Whether this step qualifies for partition batching.
  #
  # @return [Boolean]
  def batchable?
    @step.operation == "optimize" &&
      config["where"].blank? &&
      identity_partition_column.present?
  end

  # The single-column identity partition name, or nil when the table is not
  # partitioned by exactly one identity field.
  #
  # @return [String, nil]
  def identity_partition_column
    fields = partition_specs&.first&.dig("fields") || []
    return nil unless fields.size == 1

    field = fields.first
    return nil unless field["transform"] == "identity"

    field["name"].presence
  end

  # The current table's partition specs, from the metadata the app already tracks.
  #
  # @return [Array, nil]
  def partition_specs
    @table.partition_json
  end

  # Distinct partition values for the column, via $partitions.
  #
  # Trino's Iceberg $partitions metadata table exposes the partition fields
  # nested under a `partition` row/struct column - `SELECT DISTINCT
  # "ingestion_date"` fails with "Column cannot be resolved". The column must
  # be referenced as partition.<name>; `partition` is quoted because it is a
  # reserved word in SQL.
  #
  # @param column [String] the partition column name
  # @param execution_id [Integer] the execution id for header tagging
  # @return [Array] the distinct values
  def distinct_partition_values(column, execution_id)
    sql = %(SELECT DISTINCT "partition".#{quote_ident(column)} FROM #{@table.trino_metadata_table("partitions")})
    @runtime.query_rows(sql, execution_id: execution_id).map { |row| row.first }
  rescue StandardError => e
    # Partition discovery is best-effort: if it fails we fall back to the single
    # unbatched OPTIMIZE rather than failing the whole execution. But that
    # degraded path is exactly the "Exceeded limit of N open writers" failure
    # batching exists to prevent, so it must be visible to the operator - a bare
    # warn line would make "batching silently didn't happen" indistinguishable
    # from "batching wasn't needed".
    Rails.logger.warn("OptimizeStatementPlanner: partition discovery failed for " \
                      "#{@table.fully_qualified_name}: #{e.message}")
    ErrorEvent.record(catalog: @table.catalog, schema: @table.namespace, table: @table.name,
                      operation: "optimize-partition-discovery", source_system: "execution",
                      error_class: e.class.name, message: e.message,
                      context: { fallback: "single unbatched OPTIMIZE" })
    []
  end

  # The configured max partitions per statement, with the safety-margin default.
  #
  # @return [Integer]
  def partitions_per_query
    value = config["partitions_per_query"].to_i
    value.positive? ? value : DEFAULT_PARTITIONS_PER_QUERY
  end

  # The step's configuration hash.
  #
  # @return [Hash]
  def config
    @step.config || {}
  end

  # The unbatched OPTIMIZE statement (fallback / default path).
  #
  # @return [String]
  def single_statement
    MaintenanceSqlBuilder.build(@table, @step)
  end

  # Quotes an identifier for use in a WHERE clause.
  #
  # @param name [String] the identifier
  # @return [String] the quoted identifier
  def quote_ident(name)
    %("#{name.to_s.gsub('"', '""')}")
  end

  # Renders a single partition value as a safe SQL literal. Partition values are
  # dates, numbers, booleans or short strings - anything else is rejected rather
  # than shipped as raw SQL.
  #
  # @param value [Object] the value
  # @return [String] the SQL literal
  # @raise [ArgumentError] when the value cannot be rendered safely
  def sql_literal(value)
    case value
    when Numeric then value.to_s
    when true, false then value.to_s
    when String
      if value.match?(/\A\d{4}-\d{2}-\d{2}\z/) || value.match?(/\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/)
        "DATE '#{value}'"
      else
        raise ArgumentError, "unsupported partition value: #{value.inspect}"
      end
    else
      raise ArgumentError, "unsupported partition value type: #{value.class}"
    end
  end
end
