require "kubeclient"

# Thin seam over the Kubernetes API for the Trino ephemeral engine. Constructed
# with an already-configured Kubeclient so tests can swap in a fake, and the URL
# details stay out of the orchestration logic.
class K8sClient
  attr_reader :namespace, :deployment

  def initialize(kubeclient, namespace:, deployment:)
    @kubeclient = kubeclient
    @namespace = namespace
    @deployment = deployment
  end

  def scale(replicas)
    @kubeclient.patch_deployment(deployment, namespace, [ {
                                                          op: :replace,
                                                          path: "/spec/replicas",
                                                          value: replicas
                                                        } ])
  end

  def ready?
    status = @kubeclient.get_deployment(deployment, namespace).status
    status["readyReplicas"].to_i >= 1
  end

  def deployment_exists?
    @kubeclient.get_deployment(deployment, namespace)
    true
  rescue Kubeclient::ResourceNotFoundError
    false
  end
end
