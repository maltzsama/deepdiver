require "net/http"
require "json"

# Thin Net::HTTP wrapper for the JSON/API calls (catalog REST, Trino REST).
# Injected into the clients so tests can substitute a fake transport and never
# touch the network.
class HttpTransport
  class ApiError < StandardError
    attr_reader :status, :response_body

    def initialize(status, response_body)
      @status = status
      @response_body = response_body
      super("HTTP #{status}")
    end
  end

  def get(uri, headers: {})
    perform(Net::HTTP::Get.new(URI.parse(uri.to_s)), headers: headers, body: nil)
  end

  def post(uri, body:, headers: {})
    perform(Net::HTTP::Post.new(URI.parse(uri.to_s)), headers: headers, body: body)
  end

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

  def parse(body)
    return {} if body.nil? || body.empty?

    JSON.parse(body)
  end

  # Internal company CA, mounted into the pod via Secret/ConfigMap. Without it,
  # HTTPS against Polaris/Trino fails with "certificate verify failed".
  def ssl_options(uri)
    return { use_ssl: false } unless uri.scheme == "https"

    options = { use_ssl: true, open_timeout: 10, read_timeout: 60 }
    ca_file = ENV["INTERNAL_CA_FILE"]
    options[:ca_file] = ca_file if ca_file.present? && File.exist?(ca_file)
    options
  end
end
