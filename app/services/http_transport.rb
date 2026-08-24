require "net/http"
require "json"

# Thin Net::HTTP wrapper for the JSON/API calls (catalog REST, Trino REST).
# Injected into the clients so tests can substitute a fake transport and never
# touch the network.
class HttpTransport
  # Raised for non-success HTTP responses, carrying the status and body.
  class ApiError < StandardError
    attr_reader :status, :response_body

    # Creates the error with the HTTP status and response body.
    #
    # @param status [Integer] the HTTP status code
    # @param response_body [String, nil] the response body
    def initialize(status, response_body)
      @status = status
      @response_body = response_body
      super("HTTP #{status}")
    end
  end

  # Performs a GET request and parses the JSON response.
  #
  # @param uri [String] the request URI
  # @param headers [Hash] extra HTTP headers
  # @return [Hash] the parsed JSON response
  # @raise [ApiError] on non-success responses
  def get(uri, headers: {})
    perform(Net::HTTP::Get.new(URI.parse(uri.to_s)), headers: headers, body: nil)
  end

  # Performs a POST request with a body and parses the JSON response.
  #
  # @param uri [String] the request URI
  # @param body [String] the request body
  # @param headers [Hash] extra HTTP headers
  # @return [Hash] the parsed JSON response
  # @raise [ApiError] on non-success responses
  def post(uri, body:, headers: {})
    request = Net::HTTP::Post.new(URI.parse(uri.to_s))
    request["Content-Type"] = "application/json"
    perform(request, headers: headers, body: body)
  end

  # Performs a DELETE request and parses the JSON response.
  #
  # @param uri [String] the request URI
  # @param headers [Hash] extra HTTP headers
  # @return [Hash] the parsed JSON response
  # @raise [ApiError] on non-success responses
  def delete(uri, headers: {})
    perform(Net::HTTP::Delete.new(URI.parse(uri.to_s)), headers: headers, body: nil)
  end

  # The OAuth2 token endpoint expects form-urlencoded, not JSON.
  def post_form(uri, body:, headers: {})
    request = Net::HTTP::Post.new(URI.parse(uri.to_s))
    request["Content-Type"] = "application/x-www-form-urlencoded"
    perform(request, headers: headers, body: body)
  end

  private

  # Executes a request, applies headers/body and raises on non-success responses.
  #
  # @param request [Net::HTTPRequest] the request to send
  # @param headers [Hash] extra HTTP headers
  # @param body [String, nil] the request body
  # @return [Hash] the parsed JSON response
  def perform(request, headers:, body:)
    headers&.each { |key, value| request[key] = value }
    request.body = body if body

    response = Net::HTTP.start(request.uri.hostname, request.uri.port,
                               **ssl_options(request.uri)) do |http|
      http.request(request)
    end

    raise ApiError.new(response.code.to_i, response.body) unless response.is_a?(Net::HTTPSuccess)

    parse(response.body)
  end

  # Parses a JSON body, treating empty bodies as an empty hash.
  #
  # @param body [String, nil] the raw response body
  # @return [Hash] the parsed JSON
  def parse(body)
    return {} if body.nil? || body.empty?

    JSON.parse(body)
  end

  # Internal company CA, mounted into the pod via Secret/ConfigMap. Without it,
  # HTTPS against Polaris/Trino fails with "certificate verify failed".
  #
  # Timeouts apply regardless of scheme - they used to be nested under the
  # https-only branch, so a plain http:// endpoint (the default TRINO_URL is
  # one) fell back to Net::HTTP's own default instead of failing fast.
  def ssl_options(uri)
    options = { open_timeout: 10, read_timeout: 60 }
    return options.merge(use_ssl: false) unless uri.scheme == "https"

    options[:use_ssl] = true
    ca_file = ENV["INTERNAL_CA_FILE"]
    options[:ca_file] = ca_file if ca_file.present? && File.exist?(ca_file)
    options
  end
end
