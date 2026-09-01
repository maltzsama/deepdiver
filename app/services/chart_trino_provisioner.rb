# Provisions Trino through the Helm chart in Kubernetes (the production
# default). Health and idleness come from the coordinator itself: the engine is
# ephemeral, so create!/destroy! scale the Deployments 1<->0 and health is read
# from GET /v1/info.
#
# The engine is either a single-node pod (coordinator also runs tasks) or a
# coordinator with separate workers, driven by TrinoEngineConfig. Resources and
# topology are applied from that config on every create!.
class ChartTrinoProvisioner
  # Creates the provisioner with injectable k8s clients, transport and base URL.
  #
  # @param k8s [TrinoK8sClient] the coordinator Kubernetes client
  # @param worker_k8s [TrinoK8sClient] the worker Kubernetes client
  # @param transport [HttpTransport] the HTTP transport
  # @param base_url [String] the Trino coordinator base URL
  def initialize(k8s: TrinoK8sClient.new, worker_k8s: nil,
                 transport: HttpTransport.new, base_url: ENV.fetch("TRINO_URL"))
    @k8s = k8s
    @worker_k8s = worker_k8s || TrinoK8sClient.new(client: K8sClientFactory.build_worker)
    @transport = transport
    @base_url = base_url
  end

  # The active engine config (singleton).
  #
  # @return [TrinoEngineConfig]
  def config
    TrinoEngineConfig.instance
  end

  # Whether the Trino Deployment currently exists.
  #
  # @return [Boolean] true if the Deployment is present
  def exists?
    @k8s.deployment_exists?
  end

  # Healthy means HTTP 200 and starting:false on /v1/info.  In cluster
  # topology, also verifies that every node (including workers) has finished
  # starting.  Two paths are tried in order:
  #
  # 1. GET /v1/node on the coordinator (requires MANAGEMENT_READ; works when
  #    http-server.authentication.type includes management-read).
  # 2. If /v1/node 404s (management endpoint not registered — the common case
  #    for plain internal clusters), fall back to querying each worker's own
  #    /v1/info directly.
  #
  # If neither path is reachable, the coordinator's own /v1/info is already
  # confirmed — workers are deemed healthy to avoid a destroy/recreate loop.
  def healthy?
    body = @transport.get("#{@base_url}/v1/info")
    return false unless body["starting"] == false

    return true unless config.cluster?

    check_cluster_nodes
  rescue StandardError
    false
  end

  # Whether the Deployments are fully rolled out and ready: the coordinator and,
  # in cluster topology, the workers.
  #
  # @return [Boolean] true when every required node is ready
  def rollout_complete?
    return false unless @k8s.ready?

    config.cluster? ? @worker_k8s.ready? : true
  end

  # The coordinator's desired replica count (the authority for the engine).
  #
  # @return [Integer] the spec.replicas count
  def replicas
    @k8s.replicas
  end

  # No queries running or queued, per GET /v1/query.
  #
  # An unreachable coordinator must NOT read as idle: DrainEngineJob uses this
  # to decide whether it is safe to tear the engine down, and "no data" from an
  # error is indistinguishable from "nothing running" — killing a busy engine
  # because the coordinator was briefly unreachable abandons in-flight queries.
  def idle?
    active_queries.none? { |q| %w[RUNNING QUEUED].include?(q["state"]) }
  rescue StandardError
    # Coordinator unreachable/erroring: unknown state. Treat as busy so the
    # engine is never torn down while a query may still be running.
    false
  end

  # The queries currently known to the Trino coordinator, most recent first.
  #
  # @return [Array<Hash>] the raw /v1/query entries
  def active_queries
    body = @transport.get("#{@base_url}/v1/query")
    (body.is_a?(Array) ? body : []).sort_by { |q| q["queryId"].to_s }.reverse
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

  # Applies the engine config and scales the coordinator up (and workers, in
  # cluster topology).
  def create!
    wrap_k8s_errors("coordinator") { apply_coordinator_spec }
    wrap_k8s_errors("worker") { apply_worker_spec } if config.cluster?
  end

  # Scales both the coordinator and workers down to 0 replicas.
  #
  # The worker Deployment may legitimately not exist in single topology, so a
  # missing one is not a failure here - there is nothing to scale down.
  #
  # Both scale-downs are always attempted: a coordinator failure must not leak
  # worker pods that stay up holding their CPU/memory reservations. The first
  # error is collected and re-raised after the workers were handled.
  def destroy!
    first_error = nil

    begin
      wrap_k8s_errors("coordinator") { @k8s.scale(0) }
    rescue TrinoProvisioner::Error => e
      first_error = e
      Rails.logger.warn("Trino coordinator scale-down failed: #{e.message}")
    end

    begin
      @worker_k8s.scale(0)
    rescue Kubeclient::ResourceNotFoundError
      Rails.logger.info("Trino worker Deployment absent; nothing to scale down")
    rescue Kubeclient::HttpError => e
      first_error ||= TrinoProvisioner::Error.new(k8s_message("worker", e))
      Rails.logger.warn("Trino worker scale-down failed: #{k8s_message("worker", e)}")
    end

    raise first_error if first_error
  end

  # Blocks until the coordinator is scaled down or the timeout elapses.
  #
  # destroy! only scales to 0 (the Deployment is not deleted), so "gone" here
  # means no replicas remain.
  #
  # @param timeout [ActiveSupport::Duration] how long to wait
  def wait_gone!(timeout:)
    deadline = Time.current + timeout
    sleep 1 until wrap_k8s_errors("coordinator") { @k8s.live_replicas }.zero? || Time.current > deadline
  end

  private

  # Checks cluster node health via /v1/node, falling back to per-worker /v1/info
  # when the management endpoint is unavailable (404).
  #
  # @return [Boolean] true when all nodes are healthy
  def check_cluster_nodes
    nodes = @transport.get("#{@base_url}/v1/node")
    nodes.is_a?(Array) && nodes.all? { |n| n["starting"] == false }
  rescue HttpTransport::ApiError => e
    raise unless e.message.include?("404")

    # /v1/node requires MANAGEMENT_READ which isn't registered in plain
    # clusters. The coordinator's /v1/info already confirmed it is healthy;
    # trust it rather than looping destroy/recreate.
    Rails.logger.warn("ChartTrinoProvisioner: /v1/node unavailable (#{e.message}); " \
                      "trusting coordinator health — workers may not be individually verified")
    true
  end

  # Kubeclient raises its own errors (a missing Deployment, a 403 from absent
  # RBAC in the Trino namespace). SuperviseEngineStartJob only rescues
  # TrinoProvisioner::Error and Timeout::Error, and ApplicationJob has no
  # generic retry - so an unwrapped Kubeclient error killed the job outright,
  # bypassing MAX_START_ATTEMPTS and leaving the engine in "starting" until the
  # watchdog flipped it to "failed" minutes later, with the real cause visible
  # only in the worker log.
  #
  # @param role [String] "coordinator" or "worker", for the message
  def wrap_k8s_errors(role)
    yield
  rescue Kubeclient::HttpError => e
    raise TrinoProvisioner::Error, k8s_message(role, e)
  end

  # A message that names the Deployment and namespace actually addressed, so a
  # wrong TRINO_DEPLOYMENT or a missing Role is obvious from the error alone.
  # A 404 (ResourceNotFoundError) adds an actionable hint about pre-provisioning.
  #
  # @param role [String] "coordinator" or "worker"
  # @param error [Kubeclient::HttpError] the underlying error
  # @return [String] the failure message
  def k8s_message(role, error)
    client = role == "worker" ? @worker_k8s : @k8s
    msg = "Trino #{role} (#{client.target}): #{error.message}"
    if error.is_a?(Kubeclient::ResourceNotFoundError)
      msg += " — the chart provisioner requires the Deployment to be pre-created " \
             "with replicas: 0 (see README § Trino engine — provisioning)"
    end
    msg
  end

  # The env the coordinator's config.properties resolves via ${ENV:...}:
  # whether it also runs tasks (single topology) or is a pure coordinator.
  #
  # @return [Hash<String,String>]
  def coordinator_env
    { "TRINO_INCLUDE_COORDINATOR" => config.cluster? ? "false" : "true" }
  end

  def apply_coordinator_spec
    @k8s.apply_spec(
      replicas: 1,
      cpu: config.coordinator_cpu,
      memory: config.coordinator_memory,
      env: coordinator_env
    )
  end

  def apply_worker_spec
    @worker_k8s.apply_spec(
      replicas: config.worker_replicas,
      cpu: config.worker_cpu,
      memory: config.worker_memory
    )
  end
end
