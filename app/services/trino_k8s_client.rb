# TrinoK8sClient is the piece of the RealTrinoRuntime that talks to Kubernetes.
class TrinoK8sClient
  def initialize(client: nil)
    @client = client || K8sClientFactory.build
  end

  def ready?
    @client.ready?
  end

  def deployment_exists?
    @client.deployment_exists?
  end

  def scale(replicas)
    @client.scale(replicas)
  end
end
