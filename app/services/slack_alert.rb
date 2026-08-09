require "net/http"

# Minimal Slack webhook. No-op (with a logger) when the SLACK_WEBHOOK_URL env
# var is not configured.
class SlackAlert
  def self.notify(message)
    new(message).call
  end

  def initialize(message)
    @message = message
  end

  def call
    unless ENV["SLACK_WEBHOOK_URL"]
      Rails.logger.info("SlackAlert skipped (SLACK_WEBHOOK_URL not configured): #{@message}")
      return
    end

    post(ENV["SLACK_WEBHOOK_URL"])
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
