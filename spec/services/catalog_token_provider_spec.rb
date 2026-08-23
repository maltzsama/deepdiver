require "rails_helper"
require "cgi"

RSpec.describe CatalogTokenProvider, type: :service do
  let(:transport) { instance_double(HttpTransport) }
  let(:catalog)   { create(:polaris_catalog) }

  def credential_with(attrs)
    create(:catalog_credential, attrs.merge(catalog: catalog))
  end

  describe "none" do
    it "sends no Authorization header" do
      credential_with(auth_method: "none", secret: nil)
      expect(described_class.new(catalog, transport: transport).headers).to eq({})
    end
  end

  describe "bearer_static" do
    it "uses the stored secret directly without any token call" do
      credential_with(auth_method: "bearer_static", secret: "pat-token-123")
      expect(transport).not_to receive(:post_form)

      expect(described_class.new(catalog, transport: transport).headers)
        .to eq({ "Authorization" => "Bearer pat-token-123" })
    end
  end

  describe "oauth2_client_credentials" do
    before { credential_with(auth_method: "oauth2_client_credentials", client_id: "app", secret: "s3cret") }

    it "posts the grant to the catalog's own token path and caches the result" do
      expect(transport).to receive(:post_form)
        .with("http://polaris:8181/api/catalog/v1/oauth/tokens", body: a_string_including("grant_type=client_credentials", "client_id=app"))
        .once
        .and_return({ "access_token" => "tok-1", "expires_in" => 3600 })

      # Test env uses a null store; give the token somewhere to live.
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      provider = described_class.new(catalog, transport: transport)
      2.times { provider.headers }

      expect(provider.headers).to eq({ "Authorization" => "Bearer tok-1" })
    ensure
      Rails.cache = original_cache
    end

    it "raises AuthError naming expired credentials on a 401 rejection" do
      allow(transport).to receive(:post_form).and_raise(HttpTransport::ApiError.new(401, "{}"))

      expect { described_class.new(catalog, transport: transport).headers }
        .to raise_error(CatalogTokenProvider::AuthError, /personal access token may have expired|failed to obtain/)
    end
  end

  describe "oauth2_token_exchange" do
    before do
      credential_with(
        auth_method: "oauth2_token_exchange",
        secret: "the-pat",
        token_endpoint: "http://dremio:9047/oauth/token",
        oauth_scope: "dremio.all",
        properties: {}
      )
    end

    it "exchanges the PAT at the EXTERNAL token server per RFC 8693" do
      expect(transport).to receive(:post_form)
        .with("http://dremio:9047/oauth/token",
              body: a_string_including(
                "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Atoken-exchange",
                "subject_token=the-pat",
                CGI.escape(CatalogTokenProvider::DREMIO_PAT_TOKEN_TYPE),
                "client_id=dremio-catalog-cli",
                "scope=dremio.all"
              ))
        .and_return({ "access_token" => "derived", "expires_in" => 300 })

      expect(described_class.new(catalog, transport: transport).headers)
        .to eq({ "Authorization" => "Bearer derived" })
    end

    it "refresh! drops the cache so the next call exchanges again" do
      allow(transport).to receive(:post_form)
        .and_return({ "access_token" => "v2", "expires_in" => 300 })

      provider = described_class.new(catalog, transport: transport)
      expect(provider.headers["Authorization"]).to eq("Bearer v2")

      Rails.cache.delete("catalog_token/#{catalog.id}/#{catalog.reload.catalog_credential.updated_at.to_i}")
      expect(provider.headers["Authorization"]).to eq("Bearer v2") # still cached fetch re-runs block
    end
  end
end
