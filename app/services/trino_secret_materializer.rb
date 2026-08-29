# Materializes catalog credentials as a Kubernetes Secret that the Trino
# plugin mounts at /etc/baleia/secrets. Each sensitive property written by
# TrinoCatalogProjection becomes a key in this Secret.
#
# The decrypted values exist in memory only during this call — they are not
# logged, not persisted, and not included in ErrorEvent.
class TrinoSecretMaterializer
  SECRET_NAME_SUFFIX = "trino-catalog-secrets"

  # The Secret name is provided by the Helm chart through
  # TRINO_CATALOG_SECRET_NAME so it always matches the name the RBAC Role
  # authorizes via resourceNames. Computing it here from the release name
  # duplicated the chart's `fullname` logic and drifted from it: the Role
  # authorized "<release>-<chart>-trino-catalog-secrets" while this class
  # wrote "<release>-trino-catalog-secrets", so every get was a 403.
  #
  # The Secret must live where the Trino pods run (TRINO_NAMESPACE), not
  # where this pod runs - the chart grants the same RBAC in both.
  def initialize(secret_name: nil, namespace: nil, k8s_client: nil)
    @secret_name = secret_name || default_secret_name
    @namespace = namespace || default_namespace
    @k8s_client = k8s_client || default_k8s_client
  end

  # Builds the secret data from all catalogs and upserts the Secret.
  #
  # @param catalogs [Array<Catalog>] catalogs to include
  def materialize!(catalogs)
    data = {}

    catalogs.each do |catalog|
      collect_credential_keys(catalog, data)
      collect_s3_keys(catalog, data)
    end

    upsert_secret!(data)
  end

  private

  attr_reader :secret_name

  # The chart-provided name, falling back to the release-prefixed one so local
  # runs (where no chart injects the var) still work.
  def default_secret_name
    ENV["TRINO_CATALOG_SECRET_NAME"].presence ||
      "#{ENV.fetch("HELM_RELEASE", "deepdiver")}-#{SECRET_NAME_SUFFIX}"
  end

  # Trino's namespace first: the Secret is mounted by the Trino pods, so it has
  # to exist there. Falls back to this pod's namespace when they coincide.
  def default_namespace
    ENV["TRINO_NAMESPACE"].presence || ENV.fetch("K8S_NAMESPACE", "default")
  end

  # Collects catalog credential secrets (client_secret, bearer token, etc.).
  def collect_credential_keys(catalog, data)
    credential = catalog.catalog_credential
    return unless credential&.secret_set?

    props = credential.properties || {}
    props.each do |key, value|
      next unless value.is_a?(String) && value.present?

      safe_key = "catalog-#{catalog.id}-#{key.gsub('.', '_')}"
      data[safe_key] = value
    end

    # The credential secret itself
    data["catalog-#{catalog.id}-credential_secret"] = credential.secret
  end

  # Collects S3 secrets from the catalog.
  def collect_s3_keys(catalog, data)
    return if catalog.s3_authentication_type == "none"
    return unless catalog.s3_secret_key.present?

    data["catalog-#{catalog.id}-s3_secret_key"] = catalog.s3_secret_key
  end

  def upsert_secret!(data)
    secret_metadata = {
      apiVersion: "v1",
      kind: "Secret",
      metadata: {
        name: secret_name,
        namespace: @namespace,
        labels: { "app.kubernetes.io/managed-by" => "deepdiver" }
      },
      type: "Opaque",
      data: data.transform_values { |v| Base64.strict_encode64(v) }
    }

    begin
      @k8s_client.get_secret(secret_name, @namespace)
      @k8s_client.update_secret(secret_name, secret_metadata, @namespace)
    rescue Kubeclient::ResourceNotFoundError
      @k8s_client.create_secret(secret_metadata)
    end
  rescue Kubeclient::HttpError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
    # Logged at error, not warn: a swallowed failure here means Trino boots
    # without catalog credentials and maintenance fails later with a confusing
    # "catalog not found". The name/namespace are included because an RBAC
    # mismatch (403) is the likeliest cause and is invisible otherwise.
    Rails.logger.error(
      "TrinoSecretMaterializer: could not sync Secret #{@namespace}/#{secret_name} " \
      "(#{e.class}#{" HTTP #{e.error_code}" if e.respond_to?(:error_code)}): #{e.message}"
    )
    ErrorEvent.record(catalog: nil, schema: "engine", operation: "catalog-secret-sync",
                      source_system: "engine", error_class: e.class.name,
                      message: "could not sync Secret #{@namespace}/#{secret_name}: #{e.message}")
    nil
  end

  def default_k8s_client
    Kubeclient::Client.new(
      k8s_api_endpoint,
      "v1",
      auth_options: { bearer_token: K8sClientFactory.bearer_token },
      ssl_options: { ca_file: K8sClientFactory.ca_file }.compact
    )
  end

  # The Kubernetes API endpoint. In the cluster it is derived from the
  # service-account env vars; outside it falls back to KUBE_API_URL and then
  # to the well-known in-cluster service so this never raises KeyError.
  #
  # @return [String] the API endpoint URL
  def k8s_api_endpoint
    return K8sClientFactory.api_endpoint if ENV["KUBERNETES_SERVICE_HOST"].present?

    ENV.fetch("KUBE_API_URL", "https://kubernetes.default.svc")
  end
end
