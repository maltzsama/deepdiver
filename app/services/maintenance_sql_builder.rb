# Builds the exact Trino maintenance statement for a chain step, per the
# unified `ALTER TABLE ... EXECUTE` syntax. Values come from the step's config;
# when a field is left blank the Trino default is used (defaults below are the
# fallback only when the operator did not type anything).
class MaintenanceSqlBuilder
  FILE_SIZE_THRESHOLD_DEFAULT = "128MB"
  RETENTION_THRESHOLD_DEFAULT = "7d"

  # Builds the maintenance statement for a table and chain step.
  #
  # @param table [IcebergTable] the target table
  # @param step [MaintenanceStep] the step describing the operation
  # @param where [String, nil] an explicit WHERE predicate that overrides the
  #   step's configured one (used by partition-batched OPTIMIZE)
  # @return [String] the ALTER TABLE ... EXECUTE statement
  def self.build(table, step, where: nil)
    new(table, step, where: where).build
  end

  # Creates the builder for a table and step.
  #
  # @param table [IcebergTable] the target table
  # @param step [MaintenanceStep] the step describing the operation
  # @param where [String, nil] an explicit WHERE predicate
  def initialize(table, step, where: nil)
    @table = table
    @step = step
    @where = where
  end

  # Builds the full ALTER TABLE statement including its arguments.
  #
  # @return [String] the generated SQL
  def build
    base = "ALTER TABLE #{qualified_table} EXECUTE #{operation}"
    base + arguments
  end

  private

  # The operation name for the current step.
  #
  # @return [String] the operation
  def operation
    @step.operation
  end

  # The fully-qualified Trino identifier of the table.
  #
  # @return [String] the table identifier
  def qualified_table
    @table.trino_identifier
  end

  # The step's configuration hash, defaulting to empty.
  #
  # @return [Hash] the step config
  def config
    @step.config || {}
  end

  # Builds the EXECUTE argument list for the operation.
  #
  # @return [String] the arguments, or "" for operations with none
  def arguments
    case operation
    when "optimize"            then optimize_arguments
    when "expire_snapshots"    then expire_snapshots_arguments
    when "remove_orphan_files" then orphan_arguments
    when "optimize_manifests"  then ""
    end
  end

  # optimize(file_size_threshold => '128MB') WHERE <predicate>
  #
  # @return [String] the argument list, with an optional WHERE clause
  def optimize_arguments
    threshold = config["file_size_threshold"].presence || FILE_SIZE_THRESHOLD_DEFAULT
    sql = "(file_size_threshold => '#{threshold}')"
    where_clause = @where.presence || config["where"]
    sql += " WHERE #{where_clause}" if where_clause.present?
    sql
  end

  # expire_snapshots(retention_threshold => '7d', snapshot_ids => ARRAY[...])
  #
  # @return [String] the argument list
  def expire_snapshots_arguments
    retention = config["retention_threshold"].presence || RETENTION_THRESHOLD_DEFAULT
    args = [ "retention_threshold => '#{retention}'" ]
    if config["snapshot_ids"].present?
      ids = config["snapshot_ids"].to_s.split(",").map(&:strip).reject(&:blank?).join(", ")
      args << "snapshot_ids => ARRAY[#{ids}]"
    end
    "(#{args.join(', ')})"
  end

  # remove_orphan_files(retention_threshold => '7d')
  #
  # @return [String] the argument list
  def orphan_arguments
    retention = config["retention_threshold"].presence || RETENTION_THRESHOLD_DEFAULT
    "(retention_threshold => '#{retention}')"
  end
end
