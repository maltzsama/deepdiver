require "rails_helper"

RSpec.describe ChartTrinoProvisioner do
  let(:transport) { instance_double(HttpTransport) }
  let(:provisioner) { described_class.new(k8s: double("TrinoK8sClient"), transport: transport, base_url: "http://trino") }

  it "cancels a query via DELETE /v1/query/:id" do
    allow(transport).to receive(:delete).and_return({})

    expect(provisioner.cancel_query("qid-123")).to be(true)
    expect(transport).to have_received(:delete).with("http://trino/v1/query/qid-123")
  end

  it "returns false when the cancel request fails" do
    allow(transport).to receive(:delete).and_raise(HttpTransport::ApiError.new(404, ""))

    expect(provisioner.cancel_query("qid-123")).to be(false)
  end

  it "lists active queries from GET /v1/query" do
    allow(transport).to receive(:get).and_return(
      [ { "queryId" => "1", "state" => "RUNNING", "query" => "SELECT 1" } ]
    )

    expect(provisioner.active_queries.size).to eq(1)
  end
end
