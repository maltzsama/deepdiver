# Production Trino runtime: scales the ephemeral Deployment through Kubernetes
# and runs the maintenance SQL against the Trino REST endpoint.
class RealTrinoRuntime
  def initialize(k8s: TrinoK8sClient.new, rest: TrinoRestClient.new(endpoint: ENV.fetch("TRINO_URL")))
    @k8s = k8s
    @rest = rest
  end

  def ready?
    @k8s.ready?
  end

  def ensure_running
    @k8s.scale(1)
  end

  def ensure_stopped
    @k8s.scale(0)
  end

  def execute(sql, execution_id:)
    @rest.execute(sql, execution_id: execution_id)
  end
end
