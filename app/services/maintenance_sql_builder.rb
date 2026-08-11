# Builds the exact Trino maintenance statement for a chain step, per the
# unified `ALTER TABLE ... EXECUTE` syntax.
class MaintenanceSqlBuilder
  FILE_SIZE_THRESHOLD_DEFAULT = "128MB"
  RETENTION_THRESHOLD_DEFAULT = "7d"

  # Builds the maintenance statement for a table and chain step.
  #
  # @param table [IcebergTable] the target table
  # @param step [MaintenanceStep] the step describing the operation
  # @return [String] the ALTER TABLE ... EXECUTE statement
  def self.build(table, step)
    new(table, step).build
  end

  # Creates the builder for a table and step.
  #
  # @param table [IcebergTable] the target table
  # @param step [MaintenanceStep] the step describing the operation
  def initialize(table, step)
    @table = table
    @step = step
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
    when "optimize"
      "(file_size_threshold => '#{config["file_size_threshold"] || FILE_SIZE_THRESHOLD_DEFAULT}')"
    when "expire_snapshots", "remove_orphan_files"
      "(retention_threshold => '#{config["retention_threshold"] || RETENTION_THRESHOLD_DEFAULT}')"
    when "optimize_manifests"
      ""
    end
  end
end
