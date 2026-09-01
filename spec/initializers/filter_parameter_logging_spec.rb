require "rails_helper"

RSpec.describe "filter_parameter_logging" do
  it "filters slack_webhook_url from request logs" do
    filter = Rails.application.config.filter_parameters
    filtered = ActiveSupport::ParameterFilter.new(filter).filter(
      "slack_webhook_url" => "https://hooks.slack.com/services/T000/B000/secret",
      "name" => "keep me"
    )

    expect(filtered["slack_webhook_url"]).to eq("[FILTERED]")
    expect(filtered["name"]).to eq("keep me")
  end
end
