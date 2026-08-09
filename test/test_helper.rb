ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)
  include ActiveJob::TestHelper

  teardown :cleanup_trino_locks
  teardown :reset_trino_runtime

  # Test double for a runtime that raises Trino commit conflicts.
  class ConflictRuntime
    def ready?
      true
    end

    def ensure_running
    end

    def ensure_stopped
    end

    def execute(*, **)
      raise TrinoRuntime::CommitConflict, "another writer committed first"
    end
  end

  # Test double for a runtime that never becomes ready.
  class UnavailableRuntime
    def ready?
      false
    end

    def ensure_running
    end

    def ensure_stopped
    end

    def execute(*, **)
      raise "should not be called"
    end
  end

  private

  def build_catalog
    Catalog.find_or_create_by!(name: "analytics") do |catalog|
      catalog.catalog_type = "nessie"
      catalog.endpoint = "http://nessie:19120/api/v1"
    end
  end

  def build_table
    catalog = build_catalog
    catalog.iceberg_tables.find_or_create_by!(namespace: "reporting", name: "dwd_orders")
  end

  def build_schedule(operation: "optimize", config: nil, cron: "0 3 * * *", **rest)
    attrs = { operation: operation, cron: cron, **rest }
    attrs[:config] = config if config
    build_table.maintenance_schedules.create!(**attrs)
  end

  def cleanup_trino_locks
    TrinoLock.delete_all
  end

  def reset_trino_runtime
    TrinoRuntime.reset_adapter!
  end
end
