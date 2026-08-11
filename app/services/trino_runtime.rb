# Low-coupling facade for the Trino engine. Phase 3 shipped the fake adapter so
# the whole state machine runs without a cluster; Phase 5 adds the real one. Set
# TRINO_RUNTIME=real (plus the TRINO_* and KUBE_* env vars) in production.
class TrinoRuntime
  # Raised when a maintenance query fails with a commit conflict.
  class CommitConflict < StandardError; end

  # Whether the current adapter's engine is ready.
  #
  # @return [Boolean] true when ready
  def self.ready?
    adapter.ready?
  end

  # Ensures the engine is running via the current adapter.
  def self.ensure_running
    adapter.ensure_running
  end

  # Ensures the engine is stopped via the current adapter.
  def self.ensure_stopped
    adapter.ensure_stopped
  end

  # Executes SQL through the current adapter.
  #
  # @param sql [String] the query
  # @param execution_id [Integer] the execution id for tracking
  # @param execution [ExecutionHistory, nil] the execution for heartbeats
  # @return [Hash] the result payload
  def self.execute(sql, execution_id:, execution: nil)
    adapter.execute(sql, execution_id: execution_id, execution: execution)
  end

  # The cached runtime adapter, building it on first use.
  #
  # @return [TrinoRuntime] the adapter
  def self.adapter
    @adapter ||= build_adapter
  end

  # Replaces the runtime adapter (used by tests).
  #
  # @param adapter [TrinoRuntime] the adapter to use
  def self.adapter=(adapter)
    @adapter = adapter
  end

  # Clears the cached adapter so the next call rebuilds it.
  def self.reset_adapter!
    @adapter = nil
  end

  # Builds the real or fake adapter from the TRINO_RUNTIME env var.
  #
  # @return [TrinoRuntime] the adapter
  def self.build_adapter
    return RealTrinoRuntime.new if ENV["TRINO_RUNTIME"] == "real"

    FakeTrinoRuntime.new
  end
end
