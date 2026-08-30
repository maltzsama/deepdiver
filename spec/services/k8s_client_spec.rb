require "rails_helper"

RSpec.describe K8sClient do
  let(:kubeclient) { double("Kubeclient::Client") }
  let(:namespace) { "trino-ns" }
  let(:deployment) { "trino-coordinator" }
  let(:client) { described_class.new(kubeclient, namespace: namespace, deployment: deployment) }

  describe "#live_replicas" do
    it "reads status.replicas (actual running/pending pods)" do
      deployment_obj = double("deployment",
        spec: { "replicas" => 0 },
        status: { "replicas" => 2 }
      )
      allow(kubeclient).to receive(:get_deployment).with(deployment, namespace).and_return(deployment_obj)

      expect(client.live_replicas).to eq(2)
    end

    it "returns 0 when the Deployment is not found" do
      allow(kubeclient).to receive(:get_deployment)
        .and_raise(Kubeclient::ResourceNotFoundError.new(404, "not found", nil))

      expect(client.live_replicas).to eq(0)
    end

    it "returns 0 when status.replicas is nil" do
      deployment_obj = double("deployment",
        spec: { "replicas" => 0 },
        status: { "replicas" => nil }
      )
      allow(kubeclient).to receive(:get_deployment).and_return(deployment_obj)

      expect(client.live_replicas).to eq(0)
    end
  end
end
