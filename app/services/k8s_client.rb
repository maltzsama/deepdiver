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

  # The addressed Deployment as "namespace/name", for error messages: a wrong
  # TRINO_DEPLOYMENT or a Role missing in the Trino namespace is otherwise
  # indistinguishable from any other Kubernetes failure.
  #
  # @return [String] the namespace-qualified Deployment name
  def target
    "#{namespace}/#{deployment}"
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

  # Applies the engine node spec (replica count, container resources and env)
  # via a strategic-merge patch, so only the addressed fields change - existing
  # env vars and the rest of the pod template are preserved.
  #
  # @param replicas [Integer] the desired replica count
  # @param cpu [String] the CPU request/limit for the Trino container
  # @param memory [String] the memory request/limit for the Trino container
  # @param env [Hash<String,String>] environment variables to upsert
  # @param container [String] the container name (default "trino")
  def apply_spec(replicas:, cpu:, memory:, env: {}, container: "trino")
    patch = {
      spec: {
        replicas: replicas,
        template: {
          spec: {
            containers: [
              {
                name: container,
                resources: {
                  requests: { cpu: cpu, memory: memory },
                  limits:   { cpu: cpu, memory: memory }
                },
                env: env.map { |name, value| { name: name, value: value } }
              }
            ]
          }
        }
      }
    }
    @kubeclient.patch_deployment(deployment, deep_stringify(patch), namespace)
  end

  # Whether the Deployment has all desired replicas ready.
  #
  # @return [Boolean] true when readyReplicas >= spec.replicas
  def ready?
    dep = @kubeclient.get_deployment(deployment, namespace)
    dep.status["readyReplicas"].to_i >= dep.spec["replicas"].to_i
  end

  # The Deployment's desired replica count.
  #
  # @return [Integer] the spec.replicas count
  def replicas
    @kubeclient.get_deployment(deployment, namespace).spec["replicas"].to_i
  end

  # Pods not yet terminated that the Deployment still reports (status.replicas),
  # as opposed to #replicas which returns the DESIRED count (spec.replicas).
  #
  # @return [Integer] the actual running/pending pod count
  def live_replicas
    @kubeclient.get_deployment(deployment, namespace).status["replicas"].to_i
  rescue Kubeclient::ResourceNotFoundError
    0
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

  private

  # kubeclient JSON-encodes the patch, but a Hash with symbol keys would become
  # JSON with string keys anyway; normalise to strings for clarity and to avoid
  # surprises with nested strategic-merge keys.
  # @param value [Object] the value to stringify
  # @return [Object] the stringified value
  def deep_stringify(value)
    case value
    when Hash  then value.transform_keys(&:to_s).transform_values { |v| deep_stringify(v) }
    when Array then value.map { |v| deep_stringify(v) }
    else value
    end
  end
end
