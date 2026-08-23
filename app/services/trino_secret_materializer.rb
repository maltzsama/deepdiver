# Materializes catalog credentials as a Kubernetes Secret that the Trino
# plugin mounts at /etc/baleia/secrets. Each sensitive property written by
# TrinoCatalogProjection becomes a key in this Secret.
#
# The decrypted values exist in memory only during this call — they are not
# logged, not persisted, and not included in ErrorEvent.
class TrinoSecretMaterializer
  SECRET_NAME_SUFFIX = "trino-catalog-secrets"

  def initialize(release_name: ENV.fetch("HELM_RELEASE", "lakedeepdiver"),
                 namespace: ENV.fetch("K8S_NAMESPACE", "default"),
                 k8s_client: nil)
    @release_name = release_name
    @namespace = namespace
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

  def secret_name
    "#{@release_name}-#{SECRET_NAME_SUFFIX}"
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
        labels: { "app.kubernetes.io/managed-by" => "lakedeepdiver" }
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
    Rails.logger.warn("TrinoSecretMaterializer: could not sync secret (#{e.class}): #{e.message}")
    nil
  end

  def default_k8s_client
    Kubeclient::Client.new(
      ENV.fetch("KUBE_API_URL", "https://kubernetes.default.svc"),
      "v1",
      ssl_options: {
        ca_file: ENV["KUBE_CA_FILE"],
        verify_ssl: OpenSSL::SSL::VERIFY_PEER
      }
    )
  end
end
