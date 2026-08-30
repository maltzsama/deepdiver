require "rails_helper"
require "aws-sdk-sts"

RSpec.describe "Baleia secret contract" do
  let(:k8s_client) { double("Kubeclient::Client") }

  before do
    allow(k8s_client).to receive(:get_secret)
      .and_raise(Kubeclient::ResourceNotFoundError.new(404, "not found", nil))
    allow(k8s_client).to receive(:create_secret)
  end

  def stub_sts!(access_key: "ASIAIOSFODNN7TEMP", secret: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYTEMPKEY", session_token: "FwoGZXIvYXdzEBY")
    sts = instance_double(Aws::STS::Client)
    allow(Aws::STS::Client).to receive(:new).and_return(sts)
    allow(sts).to receive(:assume_role).and_return(
      double(credentials: double(
        access_key_id: access_key, secret_access_key: secret, session_token: session_token
      ))
    )
  end

  # Extracts {trino_property_key => secret_file_name} from a registry row's properties.
  def refs_from(row)
    row.properties.each_with_object({}) do |(key, value), acc|
      m = value.to_s.match(%r{\A@baleia-secret\[file:(.+)\]\z})
      acc[key] = m[1] if m
    end
  end

  # Runs the materializer, capturing the payload sent to create_secret or update_secret.
  # Returns the payload hash.
  def materialized_payload
    payload = nil
    allow(k8s_client).to receive(:create_secret) { |p| payload = p }
    allow(k8s_client).to receive(:update_secret) { |_name, p, _ns| payload = p }
    TrinoSecretMaterializer.new(k8s_client: k8s_client)
      .materialize!(Catalog.includes(:catalog_credential))
    payload
  end

  # Collects all @baleia-secret[file:NAME] refs across ALL registry rows.
  def all_registry_refs
    TrinoCatalogRegistry.pluck(:properties).flat_map do |props|
      props.map { |_k, v| v.to_s.match(%r{\A@baleia-secret\[file:(.+)\]\z})&.[](1) }.compact
    end
  end

  # Asserts a single catalog: refs emitted by the projection exactly match
  # keys written by the materializer, and no plaintext sensitive value leaks.
  def assert_contract_for(catalog_name:)
    TrinoCatalogProjection.new.sync_all!
    row = TrinoCatalogRegistry.find_by(catalog_name: catalog_name)
    refs = refs_from(row)
    payload = materialized_payload

    expect(refs).not_to be_empty, "projection should emit at least one baleia-secret ref"
    expect(refs.values).to match_array(payload[:data].keys)

    sensitive = TrinoCatalogProjection::SENSITIVE_KEYS
    row.properties.each do |key, value|
      next unless sensitive.include?(key)
      expect(value).to match(/@baleia-secret\[file:/),
        "sensitive key #{key} must be a ref, got #{value.inspect}"
    end
  end

  describe "static S3 catalog" do
    let!(:catalog) { create(:catalog, :s3_static, name: "s3-static") }

    it "refs match materializer keys and no plaintext leaks" do
      assert_contract_for(catalog_name: "s3_static")
    end
  end

  describe "STS catalog" do
    before { stub_sts! }

    let!(:catalog) { create(:catalog, :s3_sts, name: "s3-sts") }

    it "refs match materializer keys and no plaintext leaks" do
      assert_contract_for(catalog_name: "s3_sts")

      row = TrinoCatalogRegistry.find_by(catalog_name: "s3_sts")
      expect(row.properties).to have_key("s3.access-key")
      expect(row.properties).to have_key("s3.secret-key")
      expect(row.properties).to have_key("s3.session-token")
    end
  end

  describe "OAuth2 catalog" do
    let!(:catalog) do
      create(:catalog, name: "oauth2-cat", catalog_type: "nessie",
             endpoint: "http://nessie:19120/api/v1").tap do |cat|
        create(:catalog_credential, catalog: cat, auth_method: "oauth2_client_credentials",
               client_id: "svc", secret: "s3cr3t", scope: "PRINCIPAL_ROLE:ALL")
      end
    end

    it "refs match materializer keys and no plaintext leaks" do
      assert_contract_for(catalog_name: "oauth2_cat")

      row = TrinoCatalogRegistry.find_by(catalog_name: "oauth2_cat")
      expect(row.properties["iceberg.rest-catalog.oauth2.credential"])
        .to match(/\A@baleia-secret\[file:catalog-\d+-iceberg_rest-catalog_oauth2_credential\]\z/)
    end
  end

  describe "multi-catalog contract" do
    before do
      create(:catalog, :s3_static, name: "static-cat")
      oauth_catalog = create(:catalog, name: "oauth-cat", catalog_type: "nessie",
                             endpoint: "http://nessie:19120/api/v1")
      create(:catalog_credential, catalog: oauth_catalog, auth_method: "oauth2_client_credentials",
             client_id: "svc", secret: "s3cr3t", scope: "PRINCIPAL_ROLE:ALL")
    end

    it "union of refs across all registry rows matches union of Secret keys" do
      TrinoCatalogProjection.new.sync_all!
      payload = materialized_payload

      expect(all_registry_refs).not_to be_empty
      expect(all_registry_refs.sort).to eq(payload[:data].keys.sort)
    end
  end

  describe "update path (Secret already exists)" do
    let!(:catalog) { create(:catalog, :s3_static, name: "existing-cat") }

    it "writes correct payload via update_secret with no stale keys" do
      TrinoCatalogProjection.new.sync_all!

      allow(k8s_client).to receive(:get_secret) do |_name, _ns|
        { "data" => { "stale" => Base64.strict_encode64("old") } }
      end
      payload = materialized_payload

      expect(payload).not_to be_nil
      expect(payload[:data]).to have_key("catalog-#{catalog.id}-s3_secret-key")
      expect(payload[:data]).not_to have_key("stale")
    end
  end

  describe "RefreshStsCredentialsJob" do
    it "calls TrinoSecretMaterializer#materialize!" do
      stub_sts!(access_key: "ASIA", secret: "secret", session_token: "token")
      create(:catalog, :s3_sts, name: "sts-refresh")

      materializer = instance_double(TrinoSecretMaterializer)
      allow(TrinoSecretMaterializer).to receive(:new).and_return(materializer)
      allow(materializer).to receive(:materialize!)

      RefreshStsCredentialsJob.new.perform

      expect(materializer).to have_received(:materialize!)
    end
  end
end
