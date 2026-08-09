# Builds the KubeClient from explicit credentials. In the cluster we rely on the
# Pod's ServiceAccount token and CA; in dev/admin runs KUBE_API_URL + KUBE_TOKEN
# are used instead.
class K8sClientFactory
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

  def self.api_endpoint
    ENV["KUBE_API_URL"] ||
      "https://#{ENV.fetch("KUBERNETES_SERVICE_HOST")}:#{ENV.fetch("KUBERNETES_SERVICE_PORT")}"
  end

  def self.bearer_token
    ENV["KUBE_TOKEN"] || service_account_file("token")
  end

  def self.ca_file
    ENV["KUBE_CA_FILE"] || service_account_file("ca.crt")
  end

  def self.service_account_file(name)
    path = "/var/run/secrets/kubernetes.io/serviceaccount/#{name}"
    File.read(path) if File.exist?(path)
  end
end
