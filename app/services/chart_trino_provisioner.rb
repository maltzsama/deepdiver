# Provisions Trino through the Helm chart in Kubernetes (the production
# default). Health and idleness come from the coordinator itself: the engine is
# ephemeral, so create!/destroy! scale the Deployment 1<->0 and health is read
# from GET /v1/info.
class ChartTrinoProvisioner
  def initialize(k8s: TrinoK8sClient.new, transport: HttpTransport.new, base_url: ENV.fetch("TRINO_URL"))
    @k8s = k8s
    @transport = transport
    @base_url = base_url
  end

  def exists?
    @k8s.deployment_exists?
  end

  # Healthy means HTTP 200 and starting:false on /v1/info.
  def healthy?
    body = @transport.get("#{@base_url}/v1/info")
    body["starting"] == false
  rescue StandardError
    false
  end

  def rollout_complete?
    @k8s.ready?
  end

  # No queries running or queued, per GET /v1/query.
  def idle?
    body = @transport.get("#{@base_url}/v1/query")
    queries = body.is_a?(Array) ? body : []
    queries.none? { |q| %w[RUNNING QUEUED].include?(q["state"]) }
  rescue StandardError
    false
  end

  def create!
    @k8s.scale(1)
  end

  def destroy!
    @k8s.scale(0)
  end

  def wait_gone!(timeout:)
    deadline = Time.current + timeout
    sleep 1 until !exists? || Time.current > deadline
  end
end
