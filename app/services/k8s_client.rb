require "kubeclient"

# Thin seam over the Kubernetes API for the Trino ephemeral engine. Constructed
# with an already-configured Kubeclient so tests can swap in a fake, and the URL
# details stay out of the orchestration logic.
class K8sClient
  attr_reader :namespace, :deployment

  # Wraps a configured Kubeclient and the deployment coordinates.
  #
  # @param kubeclient [Kubeclient::Client] the Kubernetes API client
  # @param namespace [String] the deployment namespace
  # @param deployment [String] the deployment name
  def initialize(kubeclient, namespace:, deployment:)
    @kubeclient = kubeclient
    @namespace = namespace
    @deployment = deployment
  end

  # Sets the Deployment replica count via a JSON patch.
  #
  # @param replicas [Integer] the desired replica count
  def scale(replicas)
    @kubeclient.json_patch_deployment(
      deployment,
      [ { op: :replace, path: "/spec/replicas", value: replicas } ],
      namespace
    )
  end

  # Whether the Deployment has at least one ready replica.
  #
  # @return [Boolean] true when ready
  def ready?
    status = @kubeclient.get_deployment(deployment, namespace).status
    status["readyReplicas"].to_i >= 1
  end

  # Whether the Deployment currently exists.
  #
  # @return [Boolean] true when the Deployment is found
  def deployment_exists?
    @kubeclient.get_deployment(deployment, namespace)
    true
  rescue Kubeclient::ResourceNotFoundError
    false
  end
end
