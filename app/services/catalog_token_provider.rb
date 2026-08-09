# Fetches and keeps the catalog access token.
#
# Polaris: OAuth2 client credentials, POST <endpoint><token_path>, body
# application/x-www-form-urlencoded, response carries access_token and
# expires_in.
#
# The token is cached with a safety margin before it expires - never stored in
# the database, because it is ephemeral and there is no reason to persist one
# more secret.
class CatalogTokenProvider
  class AuthError < StandardError; end

  EXPIRY_MARGIN = 60 # seconds before the real expiry

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

  private

  def access_token
    Rails.cache.fetch(cache_key, expires_in: cached_ttl) { request_token }
  end

  def cache_key = "catalog_token/#{@catalog.id}/#{@credential.updated_at.to_i}"

  # Without knowing expires_in before the call, the cache TTL is conservative;
  # request_token rewrites it with the real value.
  def cached_ttl = 5.minutes

  def request_token
    body = URI.encode_www_form(
      grant_type: "client_credentials",
      client_id: @credential.client_id,
      client_secret: @credential.secret,
      scope: @credential.scope
    )

    response = @transport.post_form(token_url, body: body)

    token = response["access_token"]
    raise AuthError, "response without access_token" if token.blank?

    expires_in = response["expires_in"].to_i
    if expires_in.positive?
      Rails.cache.write(cache_key, token, expires_in: (expires_in - EXPIRY_MARGIN).clamp(30, 86_400))
    end

    token
  rescue HttpTransport::ApiError => e
    raise AuthError, "failed to obtain a token from the catalog: #{e.message}"
  end

  def token_url
    "#{@catalog.endpoint.chomp('/')}#{@credential.token_path}"
  end
end
