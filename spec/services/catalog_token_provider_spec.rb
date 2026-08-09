require "rails_helper"

RSpec.describe CatalogTokenProvider do
  let(:catalog) { create(:catalog, endpoint: "https://polaris.local/api/catalog") }
  let(:transport) { instance_double(HttpTransport) }

  # The test environment uses a null cache store; swap in memory for the token cache.
  before do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  after do
    Rails.cache = @original_cache
  end

  context "oauth2_client_credentials" do
    before do
      create(:catalog_credential, catalog:, auth_method: "oauth2_client_credentials",
                                  client_id: "svc", secret: "s3cr3t", scope: "PRINCIPAL_ROLE:ALL")
    end

    it "exchanges client_id/secret for an access token" do
      expect(transport).to receive(:post_form)
        .with("https://polaris.local/api/catalog/v1/oauth/tokens", hash_including(:body))
        .and_return("access_token" => "tok-123", "expires_in" => 3600)

      headers = described_class.new(catalog.reload, transport:).headers

      expect(headers).to eq("Authorization" => "Bearer tok-123")
    end

    it "does not ask for a token again while the cache is valid" do
      allow(transport).to receive(:post_form)
        .and_return("access_token" => "tok-123", "expires_in" => 3600)

      2.times { described_class.new(catalog.reload, transport:).headers }

      expect(transport).to have_received(:post_form).once
    end

    it "raises AuthError when the response carries no token" do
      allow(transport).to receive(:post_form).and_return("error" => "invalid_client")

      expect { described_class.new(catalog.reload, transport:).headers }
        .to raise_error(described_class::AuthError)
    end
  end

  it "sends no header when auth_method is none" do
    create(:catalog_credential, catalog:, auth_method: "none", secret: nil)

    expect(described_class.new(catalog.reload, transport:).headers).to eq({})
  end

  it "uses the static secret for bearer_static" do
    create(:catalog_credential, catalog:, auth_method: "bearer_static", secret: "static-tok")

    expect(described_class.new(catalog.reload, transport:).headers)
      .to eq("Authorization" => "Bearer static-tok")
  end
end
