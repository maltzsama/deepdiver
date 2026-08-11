require "net/http"

# Minimal Slack webhook. No-op (with a logger) when the SLACK_WEBHOOK_URL env
# var is not configured.
class SlackAlert
  # Convenience entry point that sends a message to a webhook.
  #
  # @param message [String] the alert text
  # @param webhook [String, nil] an optional override webhook URL
  def self.notify(message, webhook: nil)
    new(message, webhook: webhook).call
  end

  # Creates the alert with a message and optional webhook override.
  #
  # @param message [String] the alert text
  # @param webhook [String, nil] an optional override webhook URL
  def initialize(message, webhook: nil)
    @message = message
    @webhook = webhook
  end

  # Posts the alert, skipping with a log when no webhook is configured.
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

  # POSTs the JSON payload to the webhook URL.
  #
  # @param url [String] the webhook URL
  def post(url)
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = { text: "LakeDeepDiver: #{@message}" }.to_json
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
  end
end
