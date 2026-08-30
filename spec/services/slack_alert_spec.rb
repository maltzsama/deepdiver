require "rails_helper"

RSpec.describe SlackAlert do
  let(:webhook_url) { "https://hooks.slack.com/services/T00/B00/xxxxx" }

  describe "#call" do
    it "skips with a log when no webhook is configured" do
      expect(Rails.logger).to receive(:info).with(/skipped/)
      described_class.new("test message").call
    end

    it "returns true on a successful POST" do
      http = instance_double(Net::HTTP)
      response = instance_double(Net::HTTPSuccess, code: "200", body: "ok")
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(response)

      result = described_class.new("test message", webhook: webhook_url).call
      expect(result).to be true
    end

    it "logs a warning on HTTP 4xx" do
      http = instance_double(Net::HTTP)
      response = instance_double(Net::HTTPNotFound, code: "404", body: "not found")
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(response)

      expect(Rails.logger).to receive(:warn).with(/Slack webhook returned HTTP 404/)
      described_class.new("test message", webhook: webhook_url).call
    end

    it "logs a warning on HTTP 5xx" do
      http = instance_double(Net::HTTP)
      response = instance_double(Net::HTTPServiceUnavailable, code: "503", body: "unavailable")
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:request).and_return(response)

      expect(Rails.logger).to receive(:warn).with(/Slack webhook returned HTTP 503/)
      described_class.new("test message", webhook: webhook_url).call
    end

    it "includes the channel in the payload when provided" do
      http = instance_double(Net::HTTP)
      response = instance_double(Net::HTTPSuccess, code: "200", body: "ok")
      allow(Net::HTTP).to receive(:start).and_yield(http)

      captured_body = nil
      allow(http).to receive(:request) do |request|
        captured_body = request.body
        response
      end

      described_class.new("test message", webhook: webhook_url, channel: "#alerts").call

      payload = JSON.parse(captured_body)
      expect(payload["channel"]).to eq("#alerts")
    end

    it "catches network errors and logs a warning" do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect(Rails.logger).to receive(:warn).with(/Failed to send Slack alert/)
      described_class.new("test message", webhook: webhook_url).call
    end
  end
end
