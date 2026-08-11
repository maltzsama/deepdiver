# Builds the KubeClient from explicit credentials. In the cluster we rely on the
# Pod's ServiceAccount token and CA; in dev/admin runs KUBE_API_URL + KUBE_TOKEN
# are used instead.
class K8sClientFactory
  # Builds a K8sClient from the in-cluster or explicit credentials.
  #
  # @return [K8sClient] the configured client
  def self.build
    kubeclient = Kubeclient::Client.new(
      api_endpoint,
      "apps/v1",
      auth_options: { bearer_token: bearer_token },
      ssl_options: { ca_file: ca_file }.compact
    )
    K8sClient.new(kubeclient,
                  namespace: ENV.fetch("TRINO_NAMESPACE"),
                  deployment: ENV.fetch("TRINO_DEPLOYMENT"))
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
  # @return [String, nil] the CA file path
  def self.ca_file
    ENV["KUBE_CA_FILE"] || service_account_file("ca.crt")
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
