require "rails_helper"

RSpec.describe SlackAlert do
  let(:webhook_url) { "https://hooks.slack.com/services/T00/B00/xxxxx" }

  describe "#call" do
    let(:webhook_url) { "https://hooks.slack.com/services/T00/B00/xxxxx" }

    def success_response
      Net::HTTPOK.new("1.1", "200", "OK").tap { |r| r.instance_variable_set(:@read, true) }
    end

    def error_response(code, message)
      Net::HTTPNotFound.new("1.1", code.to_s, message).tap { |r| r.instance_variable_set(:@read, true) }
    end

    it "skips with a log when no webhook is configured" do
      expect(Rails.logger).to receive(:info).with(/skipped/)
      described_class.new("test message").call
    end

    it "returns true on a successful POST" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(success_response)

      result = described_class.new("test message", webhook: webhook_url).call
      expect(result).to be true
    end

    it "raises and logs a warning on HTTP 4xx" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(error_response(404, "not found"))

      expect(Rails.logger).to receive(:warn).with(/Slack webhook returned HTTP 404/)
      expect { described_class.new("test message", webhook: webhook_url).call }
        .to raise_error(/Slack webhook returned HTTP 404/)
    end

    it "raises and logs a warning on HTTP 5xx" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(error_response(503, "unavailable"))

      expect(Rails.logger).to receive(:warn).with(/Slack webhook returned HTTP 503/)
      expect { described_class.new("test message", webhook: webhook_url).call }
        .to raise_error(/Slack webhook returned HTTP 503/)
    end

    it "includes the channel in the payload when provided" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      captured_body = nil
      allow(http).to receive(:request) do |request|
        captured_body = request.body
        success_response
      end

      described_class.new("test message", webhook: webhook_url, channel: "#alerts").call

      payload = JSON.parse(captured_body)
      expect(payload["channel"]).to eq("#alerts")
    end

    it "raises and logs a warning on a network error" do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect(Rails.logger).to receive(:warn).with(/Failed to send Slack alert/)
      expect { described_class.new("test message", webhook: webhook_url).call }
        .to raise_error(Errno::ECONNREFUSED)
    end
  end
end
