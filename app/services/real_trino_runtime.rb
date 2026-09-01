# Production Trino runtime: scales the ephemeral Deployment through Kubernetes
# and runs the maintenance SQL against the Trino REST endpoint.
class RealTrinoRuntime
  # Creates the runtime with injectable k8s and REST clients.
  #
  # @param k8s [TrinoK8sClient] the Kubernetes client for scaling
  # @param rest [TrinoRestClient] the REST client for SQL execution
  def initialize(k8s: TrinoK8sClient.new, rest: TrinoRestClient.new(endpoint: ENV.fetch("TRINO_URL")))
    @k8s = k8s
    @rest = rest
  end

  # Whether the engine Deployment is ready.
  #
  # @return [Boolean] true when ready
  def ready?
    @k8s.ready?
  end

  # Scales the Deployment up to 1 replica.
  def ensure_running
    @k8s.scale(1)
  end

  # Scales the Deployment down to 0 replicas.
  def ensure_stopped
    @k8s.scale(0)
  end

  # Runs maintenance SQL through the Trino REST endpoint.
  #
  # @param sql [String] the SQL to execute
  # @param execution_id [Integer] the execution id for tracking
  # @param execution [ExecutionHistory, nil] the execution for heartbeats
  # @param step [ExecutionStep, nil] the step for query id/progress
  # @return [Hash] the metrics payload
  def execute(sql, execution_id:, execution: nil, step: nil)
    @rest.execute(sql, execution_id: execution_id, execution: execution, step: step)
  end

  # Runs a helper SQL query and returns the actual data rows.
  #
  # @param sql [String] the query
  # @param execution_id [Integer] the execution id for headers
  # @return [Array<Array>] the data rows
  def query_rows(sql, execution_id:)
    @rest.query_rows(sql, execution_id: execution_id)
  end
end
