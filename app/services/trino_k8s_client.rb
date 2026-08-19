# TrinoK8sClient is the piece of the RealTrinoRuntime that talks to Kubernetes.
class TrinoK8sClient
  # Wraps a K8sClient, building one when none is injected.
  #
  # @param client [K8sClient, nil] the underlying client
  def initialize(client: nil)
    @client = client || K8sClientFactory.build
  end

  # Whether the Trino Deployment is ready.
  #
  # @return [Boolean] true when ready
  def ready?
    @client.ready?
  end

  # The Trino Deployment's desired replica count.
  #
  # @return [Integer] the spec.replicas count
  def replicas
    @client.replicas
  end

  # Whether the Trino Deployment exists.
  #
  # @return [Boolean] true when present
  def deployment_exists?
    @client.deployment_exists?
  end

  # Scales the Trino Deployment to the given replica count.
  #
  # @param replicas [Integer] the desired replicas
  def scale(replicas)
    @client.scale(replicas)
  end
end
