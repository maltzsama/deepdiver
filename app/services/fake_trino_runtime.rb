# Skeleton Trino engine for development/tests. Immediately "ready" and returns
# canned metrics so the orchestrator can be exercised end-to-end.
class FakeTrinoRuntime
  def ready?
    true
  end

  def ensure_running
  end

  def ensure_stopped
  end

  def execute(sql, execution_id:)
    {
      "executed_sql" => sql,
      "execution_history_id" => execution_id,
      "status" => "success",
      "affected_rows" => 0
    }
  end
end
