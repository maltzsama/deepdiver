require "net/http"

# Minimal Slack webhook. No-op (with a logger) when no webhook is configured.
class SlackAlert
  # Convenience entry point that sends a message to a webhook.
  #
  # @param message [String] the alert text
  # @param webhook [String, nil] the webhook URL to post to
  # @param channel [String, nil] an optional #channel override in the payload
  def self.notify(message, webhook: nil, channel: nil)
    new(message, webhook: webhook, channel: channel).call
  end

  # Creates the alert with a message and optional webhook override.
  #
  # @param message [String] the alert text
  # @param webhook [String, nil] the webhook URL to post to
  # @param channel [String, nil] an optional #channel override in the payload
  def initialize(message, webhook: nil, channel: nil)
    @message = message
    @webhook = webhook
    @channel = channel
  end

  # Posts the alert, skipping with a log when no webhook is configured.
  #
  # A failed send RAISES so the caller can distinguish a delivered alert from a
  # rejected one — swallowing the error here made AlertNotifier report the send
  # as successful, stamp last_alert_at, and then permanently suppress further
  # alerts for the table while the webhook was dead.
  def call
    url = @webhook.presence || ENV["SLACK_WEBHOOK_URL"]
    unless url
      Rails.logger.info("SlackAlert skipped (no webhook configured): #{@message}")
      return
    end

    post(url)
  rescue StandardError => e
    Rails.logger.warn("Failed to send Slack alert: #{e.message}")
    raise
  end

  private

  # POSTs the JSON payload to the webhook URL.
  #
  # @param url [String] the webhook URL
  def post(url)
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    payload = { text: "DeepDiver: #{@message}" }
    payload[:channel] = @channel if @channel.present?
    request.body = payload.to_json
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
    unless response.is_a?(Net::HTTPSuccess)
      raise "Slack webhook returned HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
    end
    true
  end
end
