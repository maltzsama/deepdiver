require "rails_helper"

RSpec.describe TrinoSecretMaterializer do
  describe "#default_k8s_client" do
    it "authenticates against the Kubernetes API with the ServiceAccount token and CA" do
      allow(K8sClientFactory).to receive(:api_endpoint).and_return("https://k8s.example.com")
      allow(K8sClientFactory).to receive(:bearer_token).and_return("sa-token")
      allow(K8sClientFactory).to receive(:ca_file).and_return("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")

      client = described_class.new.send(:default_k8s_client)

      expect(client).to be_a(Kubeclient::Client)
      expect(client.auth_options).to eq(bearer_token: "sa-token")
      expect(client.ssl_options[:ca_file]).to eq("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
    end
  end
end
