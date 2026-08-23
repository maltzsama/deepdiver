# Skeleton Trino engine for development/tests. Immediately "ready" and returns
# canned metrics so the orchestrator can be exercised end-to-end.
class FakeTrinoRuntime
  # The fake engine is always ready.
  #
  # @return [Boolean] always true
  def ready?
    true
  end

  # No-op: the fake engine never needs starting.
  def ensure_running
  end

  # No-op: the fake engine never needs stopping.
  def ensure_stopped
  end

  # Returns a canned success result for any SQL.
  #
  # @param sql [String] the SQL to "execute"
  # @param execution_id [Integer] the execution id echoed in the result
  # @param execution [ExecutionHistory, nil] unused
  # @param step [ExecutionStep, nil] unused
  # @return [Hash] a canned success payload
  def execute(sql, execution_id:, execution: nil, step: nil)
    {
      "executed_sql" => sql,
      "execution_history_id" => execution_id,
      "status" => "success",
      "affected_rows" => 0
    }
  end
end
