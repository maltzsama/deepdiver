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
    perform(Net::HTTP::Get.new(uri), headers: headers, body: nil)
  end

  def post(uri, body:, headers: {})
    perform(Net::HTTP::Post.new(uri), headers: headers, body: body)
  end

  def delete(uri, headers: {})
    perform(Net::HTTP::Delete.new(uri), headers: headers, body: nil)
  end

  private

  def perform(request, headers:, body:)
    headers&.each { |key, value| request[key] = value }
    request.body = body if body

    response = Net::HTTP.start(request.uri.hostname, request.uri.port,
                               use_ssl: request.uri.scheme == "https") do |http|
      http.request(request)
    end

    raise ApiError.new(response.code.to_i, response.body) unless response.is_a?(Net::HTTPSuccess)

    parse(response.body)
  end

  def parse(body)
    return {} if body.nil? || body.empty?

    JSON.parse(body)
  end
end
