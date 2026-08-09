# Builds the exact Trino maintenance statement for a chain step, per the
# unified `ALTER TABLE ... EXECUTE` syntax.
class MaintenanceSqlBuilder
  FILE_SIZE_THRESHOLD_DEFAULT = "128MB"
  RETENTION_THRESHOLD_DEFAULT = "7d"

  def self.build(table, step)
    new(table, step).build
  end

  def initialize(table, step)
    @table = table
    @step = step
  end

  def build
    base = "ALTER TABLE #{qualified_table} EXECUTE #{operation}"
    base + arguments
  end

  private

  def operation
    @step.operation
  end

  def qualified_table
    @table.trino_identifier
  end

  def config
    @step.config || {}
  end

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
