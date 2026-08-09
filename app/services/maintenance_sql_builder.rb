# Builds the exact Trino maintenance statement for a schedule, per the unified
# `ALTER TABLE ... EXECUTE` syntax.
class MaintenanceSqlBuilder
  FILE_SIZE_THRESHOLD_DEFAULT = "128MB"
  RETENTION_THRESHOLD_DEFAULT = "7d"

  def self.build(schedule)
    new(schedule).build
  end

  def initialize(schedule)
    @schedule = schedule
    @table = schedule.iceberg_table
    @catalog = @table.catalog
  end

  def build
    base = "ALTER TABLE #{qualified_table} EXECUTE #{operation}"
    base + arguments
  end

  private

  def operation
    @schedule.operation
  end

  def qualified_table
    "iceberg.#{@catalog.name}.#{@table.namespace}.#{@table.name}"
  end

  def config
    @schedule.config || {}
  end

  def arguments
    case operation
    when "optimize"
      "(file_size_threshold => '#{config["file_size_threshold"] || FILE_SIZE_THRESHOLD_DEFAULT}')"
    when "expire_snapshots", "remove_orphan_files"
      "(retention_threshold => '#{config["retention_threshold"] || RETENTION_THRESHOLD_DEFAULT}')"
    when "rewrite_manifests"
      ""
    end
  end
end
