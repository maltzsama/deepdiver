# Builds the KubeClient from explicit credentials. In the cluster we rely on the
# Pod's ServiceAccount token and CA; in dev/admin runs KUBE_API_URL + KUBE_TOKEN
# are used instead.
class K8sClientFactory
  # Builds a K8sClient for the coordinator Deployment.
  #
  # @return [K8sClient] the configured client
  def self.build
    build_for(ENV.fetch("TRINO_DEPLOYMENT"))
  end

  # Builds a K8sClient for the worker Deployment.
  #
  # @return [K8sClient] the configured client
  def self.build_worker
    build_for(ENV.fetch("TRINO_WORKER_DEPLOYMENT", "trino-worker"))
  end

  # Builds a K8sClient from explicit credentials, targeting a specific
  # Deployment. In the cluster we rely on the Pod's ServiceAccount token and CA;
  # in dev/admin runs KUBE_API_URL + KUBE_TOKEN are used instead.
  #
  # @param deployment [String] the Deployment name to manage
  # @return [K8sClient] the configured client
  def self.build_for(deployment)
    kubeclient = Kubeclient::Client.new(
      apps_endpoint,
      "v1",
      auth_options: { bearer_token: bearer_token },
      ssl_options: { ca_file: ca_file }.compact
    )
    K8sClient.new(kubeclient,
                  namespace: ENV.fetch("TRINO_NAMESPACE"),
                  deployment: deployment)
  end

  # The base endpoint for the apps/v1 group. kubeclient builds the discovery
  # URL by appending the version, so the endpoint must already carry /apis/apps
  # (passing "apps/v1" as the version would produce /api/apps/v1, which is the
  # wrong path and fails discovery with a Forbidden on the core group).
  #
  # @return [String] the apps/v1 endpoint URL
  def self.apps_endpoint
    "#{api_endpoint.chomp('/')}/apis/apps"
  end

  # The Kubernetes API endpoint, from env vars or the in-cluster service.
  #
  # @return [String] the API endpoint URL
  def self.api_endpoint
    ENV["KUBE_API_URL"] ||
      "https://#{ENV.fetch("KUBERNETES_SERVICE_HOST")}:#{ENV.fetch("KUBERNETES_SERVICE_PORT")}"
  end

  # The bearer token for the Kubernetes API.
  #
  # @return [String] the token
  def self.bearer_token
    ENV["KUBE_TOKEN"] || service_account_file("token")
  end

  # The CA certificate file used to verify the API TLS connection.
  #
  # kubeclient expects a file PATH here (it calls SSL_CTX_load_verify_file),
  # not the certificate contents.
  #
  # @return [String, nil] the CA file path
  def self.ca_file
    ENV["KUBE_CA_FILE"] || service_account_file_path("ca.crt")
  end

  # The path of a service-account secret file, if present.
  #
  # @param name [String] the secret file name
  # @return [String, nil] the file path
  def self.service_account_file_path(name)
    path = "/var/run/secrets/kubernetes.io/serviceaccount/#{name}"
    path if File.exist?(path)
  end

  # Reads a service-account secret file, if present.
  #
  # @param name [String] the secret file name
  # @return [String, nil] the file contents
  def self.service_account_file(name)
    path = "/var/run/secrets/kubernetes.io/serviceaccount/#{name}"
    File.read(path) if File.exist?(path)
  end
end
