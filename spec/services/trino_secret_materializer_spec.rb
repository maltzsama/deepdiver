require "rails_helper"

RSpec.describe TrinoSecretMaterializer do
  describe "#default_k8s_client" do
    around do |example|
      original_host = ENV["KUBERNETES_SERVICE_HOST"]
      original_port = ENV["KUBERNETES_SERVICE_PORT"]
      original_api = ENV["KUBE_API_URL"]
      example.run
    ensure
      ENV["KUBERNETES_SERVICE_HOST"] = original_host
      ENV["KUBERNETES_SERVICE_PORT"] = original_port
      ENV["KUBE_API_URL"] = original_api
    end

    it "authenticates with the ServiceAccount token and CA" do
      allow(K8sClientFactory).to receive(:bearer_token).and_return("sa-token")
      allow(K8sClientFactory).to receive(:ca_file).and_return("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")

      client = described_class.new.send(:default_k8s_client)

      expect(client).to be_a(Kubeclient::Client)
      expect(client.auth_options).to eq(bearer_token: "sa-token")
      expect(client.ssl_options[:ca_file]).to eq("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
    end

    it "uses the in-cluster endpoint when inside Kubernetes" do
      ENV["KUBERNETES_SERVICE_HOST"] = "10.0.0.1"
      ENV["KUBERNETES_SERVICE_PORT"] = "443"
      ENV["KUBE_API_URL"] = nil

      endpoint = described_class.new.send(:k8s_api_endpoint)

      expect(endpoint).to eq("https://10.0.0.1:443")
    end

    it "falls back to KUBE_API_URL outside the cluster" do
      ENV["KUBERNETES_SERVICE_HOST"] = nil
      ENV["KUBE_API_URL"] = "https://k8s.example.com"

      endpoint = described_class.new.send(:k8s_api_endpoint)

      expect(endpoint).to eq("https://k8s.example.com")
    end

    it "never raises KeyError outside the cluster without KUBE_API_URL" do
      ENV["KUBERNETES_SERVICE_HOST"] = nil
      ENV["KUBE_API_URL"] = nil

      expect(described_class.new.send(:k8s_api_endpoint)).to eq("https://kubernetes.default.svc")
    end
  end
end
