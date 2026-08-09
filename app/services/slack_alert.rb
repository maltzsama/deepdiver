require "net/http"

# Minimal Slack webhook. No-op (with a logger) when the SLACK_WEBHOOK_URL env
# var is not configured.
class SlackAlert
  def self.notify(message, webhook: nil)
    new(message, webhook: webhook).call
  end

  def initialize(message, webhook: nil)
    @message = message
    @webhook = webhook
  end

  def call
    url = @webhook.presence || ENV["SLACK_WEBHOOK_URL"]
    unless url
      Rails.logger.info("SlackAlert skipped (no webhook configured): #{@message}")
      return
    end

    post(url)
  rescue StandardError => e
    Rails.logger.warn("Failed to send Slack alert: #{e.message}")
  end

  private

  def post(url)
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = { text: "LakeDeepDiver: #{@message}" }.to_json
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
  end
end
