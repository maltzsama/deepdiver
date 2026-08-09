# Low-coupling facade for the Trino engine. Phase 3 shipped the fake adapter so
# the whole state machine runs without a cluster; Phase 5 adds the real one. Set
# TRINO_RUNTIME=real (plus the TRINO_* and KUBE_* env vars) in production.
class TrinoRuntime
  class CommitConflict < StandardError; end

  def self.ready?
    adapter.ready?
  end

  def self.ensure_running
    adapter.ensure_running
  end

  def self.ensure_stopped
    adapter.ensure_stopped
  end

  def self.execute(sql, execution_id:, execution: nil)
    adapter.execute(sql, execution_id: execution_id, execution: execution)
  end

  def self.adapter
    @adapter ||= build_adapter
  end

  def self.adapter=(adapter)
    @adapter = adapter
  end

  def self.reset_adapter!
    @adapter = nil
  end

  def self.build_adapter
    return RealTrinoRuntime.new if ENV["TRINO_RUNTIME"] == "real"

    FakeTrinoRuntime.new
  end
end
