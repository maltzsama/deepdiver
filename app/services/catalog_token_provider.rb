# Fetches and keeps the catalog access token.
#
# Strategies, selected by CatalogCredential#auth_method:
#   none                        -> no Authorization header
#   bearer_static               -> the stored secret IS the Bearer token
#   oauth2_client_credentials   -> POST {endpoint}{token_path}, grant client_credentials (Polaris)
#   oauth2_token_exchange       -> RFC 8693 at an EXTERNAL token server (Dremio:
#                                  a PAT is the subject token; the catalog at
#                                  :8181 and the token server at :9047 differ)
#
# Derived tokens are cached with a safety margin before expiry and NEVER
# persisted - only the encrypted secret is. A stale cached token surfacing as
# HTTP 401 mid-sync is handled by #refresh!.
class CatalogTokenProvider
  # Raised when the catalog cannot issue a token or rejects ours.
  class AuthError < StandardError; end

  EXPIRY_MARGIN = 60 # seconds before the real expiry

  DEFAULT_EXCHANGE_CLIENT_ID = "dremio-catalog-cli"
  DREMIO_PAT_TOKEN_TYPE = "urn:ietf:params:oauth:token-type:dremio:personal-access-token"

  # Creates the token provider for a catalog with an injectable transport.
  #
  # @param catalog [Catalog] the catalog to authenticate against
  # @param transport [HttpTransport] the HTTP transport to use
  def initialize(catalog, transport: HttpTransport.new)
    @catalog = catalog
    @credential = catalog.catalog_credential
    @transport = transport
  end

  # Returns the ready-to-send authentication headers.
  def headers
    return {} if @credential.nil? || @credential.none?
    return { "Authorization" => "Bearer #{@credential.secret}" } if @credential.auth_method == "bearer_static"

    { "Authorization" => "Bearer #{access_token}" }
  end

  # Drops the cached derived token so the next #headers performs a fresh
  # exchange. Used when the catalog answers 401 to an otherwise valid request:
  # for token-exchange catalogs that means the short-lived token expired
  # mid-sync - a refresh fixes it, retrying with the same PAT failure would not.
  def refresh!
    Rails.cache.delete(cache_key) if @credential.present?
  end

  private

  # Returns a cached, still-valid access token, requesting one on a miss.
  #
  # Deliberately not Rails.cache.fetch: fetch writes the block's result itself,
  # with the TTL passed to fetch, which silently discarded the real expires_in
  # the token response carries. A token valid for less than the fallback TTL
  # was then served after it had expired.
  #
  # @return [String] the access token
  def access_token
    cached = Rails.cache.read(cache_key)
    return cached if cached.present?

    token, ttl = request_token
    Rails.cache.write(cache_key, token, expires_in: ttl)
    token
  end

  # Cache key that changes whenever the credential (or its secret) changes.
  #
  # @return [String] the Rails cache key
  def cache_key = "catalog_token/#{@catalog.id}/#{@credential.updated_at.to_i}"

  # Fallback TTL for a provider that omits expires_in from the response.
  def cached_ttl = 5.minutes

  # Performs the configured OAuth2 grant.
  #
  # @return [Array(String, ActiveSupport::Duration)] the token and its cache TTL
  # @raise [AuthError] if the token request fails or returns no token
  def request_token
    body = if @credential.token_exchange?
             URI.encode_www_form(exchange_params)
    else
             URI.encode_www_form(
               grant_type: "client_credentials",
               client_id: @credential.client_id,
               client_secret: @credential.secret,
               scope: @credential.oauth_scope.presence || @credential.scope.presence
             )
    end

    response = @transport.post_form(token_url, body: body)

    token = response["access_token"]
    raise AuthError, "response without access_token" if token.blank?

    [ token, token_ttl(response["expires_in"].to_i) ]
  rescue HttpTransport::ApiError => e
    raise AuthError, auth_failure_message(e)
  end

  # Cache TTL derived from the response's expires_in, kept a margin short of the
  # real expiry so a token is never handed out on its last second. Falls back to
  # cached_ttl when the provider omits expires_in.
  #
  # @param expires_in [Integer] seconds reported by the provider (0 when absent)
  # @return [ActiveSupport::Duration] the TTL to cache the token for
  def token_ttl(expires_in)
    return cached_ttl unless expires_in.positive?

    (expires_in - EXPIRY_MARGIN).clamp(30, 86_400).seconds
  end

  # RFC 8693 token-exchange form: the stored secret is the subject token (the
  # PAT); provider knobs come from the credential's properties bag.
  #
  # @return [Hash] urlencoded-ready params
  def exchange_params
    {
      grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
      subject_token: @credential.secret,
      subject_token_type: @credential.properties["subject_token_type"].presence || DREMIO_PAT_TOKEN_TYPE,
      client_id: @credential.properties["exchange_client_id"].presence || @credential.client_id.presence || DEFAULT_EXCHANGE_CLIENT_ID,
      scope: @credential.oauth_scope.presence || "dremio.all"
    }
  end

  # Error copy that tells the operator WHAT broke: an expired PAT kills the
  # whole catalog sync, a missing privilege kills one table - different fixes.
  #
  # @param error [HttpTransport::ApiError] the transport failure
  # @return [String] the human-facing reason
  def auth_failure_message(error)
    base = "authentication failed against #{token_url}: #{error.message}"
    return "#{base} - the personal access token may have expired; rotate it on the credential" if error.status == 401 || error.status == 403

    base
  end

  # Absolute URL of the OAuth2 token endpoint. Token exchange targets the
  # EXTERNAL token server; the other grants target the catalog itself.
  #
  # @return [String] the token endpoint URL
  def token_url
    return @credential.token_endpoint if @credential.token_exchange?

    "#{@catalog.endpoint.chomp('/')}#{@credential.token_path}"
  end
end
