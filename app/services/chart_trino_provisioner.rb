# Provisions Trino through the Helm chart in Kubernetes (the production
# default). Health and idleness come from the coordinator itself: the engine is
# ephemeral, so create!/destroy! scale the Deployment 1<->0 and health is read
# from GET /v1/info.
class ChartTrinoProvisioner
  # Creates the provisioner with injectable k8s client, transport and base URL.
  #
  # @param k8s [TrinoK8sClient] the Kubernetes client
  # @param transport [HttpTransport] the HTTP transport
  # @param base_url [String] the Trino coordinator base URL
  def initialize(k8s: TrinoK8sClient.new, transport: HttpTransport.new, base_url: ENV.fetch("TRINO_URL"))
    @k8s = k8s
    @transport = transport
    @base_url = base_url
  end

  # Whether the Trino Deployment currently exists.
  #
  # @return [Boolean] true if the Deployment is present
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

  # Whether the Deployment is fully rolled out and ready.
  #
  # @return [Boolean] true when at least one replica is ready
  def rollout_complete?
    @k8s.ready?
  end

  # The Deployment's desired replica count.
  #
  # @return [Integer] the spec.replicas count
  def replicas
    @k8s.replicas
  end

  # No queries running or queued, per GET /v1/query.
  def idle?
    active_queries.none? { |q| %w[RUNNING QUEUED].include?(q["state"]) }
  end

  # The queries currently known to the Trino coordinator, most recent first.
  #
  # @return [Array<Hash>] the raw /v1/query entries
  def active_queries
    body = @transport.get("#{@base_url}/v1/query")
    (body.is_a?(Array) ? body : []).sort_by { |q| q["queryId"].to_s }.reverse
  rescue StandardError
    []
  end

  # Cancels a running or queued query on the coordinator. Tolerates a query that
  # already finished (returns false) without raising.
  #
  # @param query_id [String] the Trino query id to cancel
  # @return [Boolean] true when the DELETE was accepted
  def cancel_query(query_id)
    @transport.delete("#{@base_url}/v1/query/#{query_id}")
    true
  rescue StandardError
    false
  end

  # Scales the Deployment up to 1 replica.
  def create!
    @k8s.scale(1)
  end

  # Scales the Deployment down to 0 replicas.
  def destroy!
    @k8s.scale(0)
  end

  # Blocks until the Deployment is scaled down or the timeout elapses.
  #
  # destroy! only scales to 0 (the Deployment is not deleted), so "gone" here
  # means no replicas remain.
  #
  # @param timeout [ActiveSupport::Duration] how long to wait
  def wait_gone!(timeout:)
    deadline = Time.current + timeout
    sleep 1 until @k8s.replicas.zero? || Time.current > deadline
  end
end
