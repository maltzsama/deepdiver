require "rails_helper"
require "aws-sdk-sts"

RSpec.describe "Baleia secret contract" do
  let(:k8s_client) { double("Kubeclient::Client") }

  before do
    allow(k8s_client).to receive(:get_secret)
      .and_raise(Kubeclient::ResourceNotFoundError.new(404, "not found", nil))
    allow(k8s_client).to receive(:create_secret)
  end

  describe "static S3 catalog" do
    let!(:catalog) { create(:catalog, :s3_static, name: "s3-static") }

    it "refs from connector_properties exactly match materializer keys" do
      TrinoCatalogProjection.new.sync_all!

      row = TrinoCatalogRegistry.find_by(catalog_name: "s3_static")
      ref_keys = row.properties.each_with_object({}) do |(prop_key, value), acc|
        match = value.to_s.match(%r{\A@baleia-secret\[file:(.+)\]\z})
        acc[prop_key] = match[1] if match
      end

      secret_data = nil
      allow(k8s_client).to receive(:create_secret) { |payload| secret_data = payload }
      allow(k8s_client).to receive(:update_secret)

      materializer = TrinoSecretMaterializer.new(k8s_client: k8s_client)
      materializer.materialize!(Catalog.includes(:catalog_credential))

      expect(ref_keys).not_to be_empty, "projection should emit at least one baleia-secret ref"
      expect(ref_keys.values).to match_array(secret_data[:data].keys.sort)

      # No plaintext sensitive value in the registry
      sensitive = TrinoCatalogProjection::SENSITIVE_KEYS
      row.properties.each do |prop_key, value|
        next unless sensitive.include?(prop_key)
        expect(value).to match(/@baleia-secret\[file:/),
          "sensitive key #{prop_key} must be a ref, got #{value.inspect}"
      end
    end
  end

  describe "STS catalog" do
    let(:sts_client) { instance_double(Aws::STS::Client) }

    before do
      allow(Aws::STS::Client).to receive(:new).and_return(sts_client)
      allow(sts_client).to receive(:assume_role).and_return(
        double(credentials: double(
          access_key_id: "ASIAIOSFODNN7TEMP",
          secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYTEMPKEY",
          session_token: "FwoGZXIvYXdzEBY"
        ))
      )
    end

    let!(:catalog) { create(:catalog, :s3_sts, name: "s3-sts") }

    it "refs from connector_properties exactly match materializer keys" do
      TrinoCatalogProjection.new.sync_all!

      row = TrinoCatalogRegistry.find_by(catalog_name: "s3_sts")
      ref_keys = row.properties.each_with_object({}) do |(prop_key, value), acc|
        match = value.to_s.match(%r{\A@baleia-secret\[file:(.+)\]\z})
        acc[prop_key] = match[1] if match
      end

      secret_data = nil
      allow(k8s_client).to receive(:create_secret) { |payload| secret_data = payload }
      allow(k8s_client).to receive(:update_secret)

      materializer = TrinoSecretMaterializer.new(k8s_client: k8s_client)
      materializer.materialize!(Catalog.includes(:catalog_credential))

      expect(ref_keys).not_to be_empty, "projection should emit at least one baleia-secret ref"
      expect(ref_keys.values).to match_array(secret_data[:data].keys.sort)

      # All 3 STS keys present as refs
      expect(row.properties).to have_key("s3.access-key")
      expect(row.properties).to have_key("s3.secret-key")
      expect(row.properties).to have_key("s3.session-token")
    end
  end

  describe "OAuth2 catalog" do
    let!(:catalog) { create(:catalog, name: "oauth2-cat", catalog_type: "nessie", endpoint: "http://nessie:19120/api/v1") }

    before do
      create(:catalog_credential, catalog: catalog, auth_method: "oauth2_client_credentials",
                                  client_id: "svc", secret: "s3cr3t", scope: "PRINCIPAL_ROLE:ALL")
    end

    it "refs from connector_properties exactly match materializer keys" do
      TrinoCatalogProjection.new.sync_all!

      row = TrinoCatalogRegistry.find_by(catalog_name: catalog.trino_catalog_name)
      ref_keys = row.properties.each_with_object({}) do |(prop_key, value), acc|
        match = value.to_s.match(%r{\A@baleia-secret\[file:(.+)\]\z})
        acc[prop_key] = match[1] if match
      end

      secret_data = nil
      allow(k8s_client).to receive(:create_secret) { |payload| secret_data = payload }
      allow(k8s_client).to receive(:update_secret)

      materializer = TrinoSecretMaterializer.new(k8s_client: k8s_client)
      materializer.materialize!(Catalog.includes(:catalog_credential))

      expect(ref_keys).not_to be_empty, "projection should emit at least one baleia-secret ref"
      expect(ref_keys.values).to match_array(secret_data[:data].keys.sort)

      # OAuth2 credential ref present
      expect(row.properties["iceberg.rest-catalog.oauth2.credential"])
        .to match(/\A@baleia-secret\[file:catalog-\d+-iceberg_rest-catalog_oauth2_credential\]\z/)
    end
  end

  describe "RefreshStsCredentialsJob" do
    it "calls TrinoSecretMaterializer#materialize!" do
      sts_client = instance_double(Aws::STS::Client)
      allow(Aws::STS::Client).to receive(:new).and_return(sts_client)
      allow(sts_client).to receive(:assume_role).and_return(
        double(credentials: double(
          access_key_id: "ASIA", secret_access_key: "secret", session_token: "token"
        ))
      )
      create(:catalog, :s3_sts, name: "sts-refresh")

      materializer = instance_double(TrinoSecretMaterializer)
      allow(TrinoSecretMaterializer).to receive(:new).and_return(materializer)
      allow(materializer).to receive(:materialize!)

      RefreshStsCredentialsJob.new.perform

      expect(materializer).to have_received(:materialize!)
    end
  end

  describe "multi-catalog contract" do
    it "union of refs across ALL registry rows matches union of Secret keys" do
      sts_client = instance_double(Aws::STS::Client)
      allow(Aws::STS::Client).to receive(:new).and_return(sts_client)
      allow(sts_client).to receive(:assume_role).and_return(
        double(credentials: double(
          access_key_id: "ASIA", secret_access_key: "sts-secret", session_token: "sts-token"
        ))
      )
      create(:catalog, :s3_static, name: "static-cat")
      oauth_catalog = create(:catalog, name: "oauth-cat", catalog_type: "nessie",
                             endpoint: "http://nessie:19120/api/v1")
      create(:catalog_credential, catalog: oauth_catalog, auth_method: "oauth2_client_credentials",
                                  client_id: "svc", secret: "s3cr3t", scope: "PRINCIPAL_ROLE:ALL")

      TrinoCatalogProjection.new.sync_all!

      all_refs = TrinoCatalogRegistry.pluck(:properties).flat_map do |props|
        props.map { |_k, v| v.to_s.match(%r{\A@baleia-secret\[file:(.+)\]\z})&.[](1) }.compact
      end

      secret_data = nil
      allow(k8s_client).to receive(:create_secret) { |payload| secret_data = payload }
      allow(k8s_client).to receive(:update_secret)
      TrinoSecretMaterializer.new(k8s_client: k8s_client)
        .materialize!(Catalog.includes(:catalog_credential))

      expect(all_refs).not_to be_empty
      expect(all_refs.sort).to eq(secret_data[:data].keys.sort)
    end
  end

  describe "update path (Secret already exists)" do
    it "writes the correct payload via update_secret" do
      create(:catalog, :s3_static, name: "existing-cat")
      TrinoCatalogProjection.new.sync_all!

      allow(k8s_client).to receive(:get_secret) do |_name, _ns|
        { "data" => { "stale" => Base64.strict_encode64("old") } }
      end
      update_payload = nil
      allow(k8s_client).to receive(:update_secret) { |name, payload, _ns| update_payload = payload }

      TrinoSecretMaterializer.new(k8s_client: k8s_client)
        .materialize!(Catalog.includes(:catalog_credential))

      expect(update_payload).not_to be_nil
      expect(update_payload[:data]).to have_key("catalog-#{Catalog.first.id}-s3_secret-key")
      expect(update_payload[:data]).not_to have_key("stale")
    end
  end
end
