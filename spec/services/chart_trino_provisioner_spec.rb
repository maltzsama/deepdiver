require "rails_helper"

RSpec.describe ChartTrinoProvisioner do
  let(:transport)  { instance_double(HttpTransport) }
  let(:k8s)        { double("coordinator k8s") }
  let(:worker_k8s) { double("worker k8s") }
  let(:provisioner) do
    described_class.new(k8s: k8s, worker_k8s: worker_k8s, transport: transport, base_url: "http://trino")
  end

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

  it "wait_gone! returns once the deployment is scaled to zero" do
    allow(k8s).to receive(:live_replicas).and_return(0)

    expect(provisioner.wait_gone!(timeout: 5.seconds)).to be_nil
    expect(k8s).to have_received(:live_replicas)
  end

  it "wait_gone! polls status.replicas (not spec.replicas) when waiting for pods to terminate" do
    call_count = 0
    allow(k8s).to receive(:live_replicas) do
      call_count += 1
      call_count <= 2 ? 2 : 0
    end
    allow(provisioner).to receive(:sleep)

    provisioner.wait_gone!(timeout: 10.seconds)

    expect(k8s).to have_received(:live_replicas).at_least(:twice)
  end

  it "wait_gone! returns when the timeout expires even if pods remain" do
    allow(k8s).to receive(:live_replicas).and_return(2)
    allow(provisioner).to receive(:sleep)

    provisioner.wait_gone!(timeout: 0.seconds)

    expect(k8s).to have_received(:live_replicas).at_least(:once)
  end

  it "reports the desired replica count from the k8s client" do
    allow(k8s).to receive(:replicas).and_return(2)

    expect(provisioner.replicas).to eq(2)
  end

  describe "#idle?" do
    it "returns true when no queries are running or queued" do
      allow(transport).to receive(:get).with("http://trino/v1/query")
        .and_return([ { "queryId" => "1", "state" => "FINISHED" } ])

      expect(provisioner.idle?).to be true
    end

    it "returns false when a query is running" do
      allow(transport).to receive(:get).with("http://trino/v1/query")
        .and_return([ { "queryId" => "1", "state" => "RUNNING" } ])

      expect(provisioner.idle?).to be false
    end

    it "returns false (busy) when the coordinator is unreachable" do
      allow(transport).to receive(:get).with("http://trino/v1/query")
        .and_raise(HttpTransport::ApiError.new(500, "coordinator down"))

      expect(provisioner.idle?).to be false
    end
  end

  describe "#healthy?" do
    it "checks coordinator starting flag from /v1/info in single topology" do
      TrinoEngineConfig.instance.update!(topology: "single")
      allow(transport).to receive(:get).with("http://trino/v1/info").and_return("starting" => false)

      expect(provisioner.healthy?).to be true
    end

    it "returns false when coordinator is still starting" do
      TrinoEngineConfig.instance.update!(topology: "single")
      allow(transport).to receive(:get).with("http://trino/v1/info").and_return("starting" => true)

      expect(provisioner.healthy?).to be false
    end

    it "checks all nodes via /v1/node in cluster topology" do
      TrinoEngineConfig.instance.update!(topology: "cluster")
      allow(transport).to receive(:get).with("http://trino/v1/info").and_return("starting" => false)
      allow(transport).to receive(:get).with("http://trino/v1/node").and_return([
        { "starting" => false, "coordinator" => true },
        { "starting" => false, "coordinator" => false }
      ])

      expect(provisioner.healthy?).to be true
    end

    it "returns false in cluster topology when a worker is still starting" do
      TrinoEngineConfig.instance.update!(topology: "cluster")
      allow(transport).to receive(:get).with("http://trino/v1/info").and_return("starting" => false)
      allow(transport).to receive(:get).with("http://trino/v1/node").and_return([
        { "starting" => false, "coordinator" => true },
        { "starting" => true, "coordinator" => false }
      ])

      expect(provisioner.healthy?).to be false
    end

    it "returns false when /v1/info fails" do
      allow(transport).to receive(:get).with("http://trino/v1/info").and_raise(StandardError)

      expect(provisioner.healthy?).to be false
    end

    it "trusts coordinator health when /v1/node 404s (management endpoint not registered)" do
      TrinoEngineConfig.instance.update!(topology: "cluster")
      allow(transport).to receive(:get).with("http://trino/v1/info").and_return("starting" => false)
      allow(transport).to receive(:get).with("http://trino/v1/node")
        .and_raise(HttpTransport::ApiError.new(404, "Not Found"))

      expect(provisioner.healthy?).to be true
    end

    it "returns false when /v1/node fails with a non-404 error" do
      TrinoEngineConfig.instance.update!(topology: "cluster")
      allow(transport).to receive(:get).with("http://trino/v1/info").and_return("starting" => false)
      allow(transport).to receive(:get).with("http://trino/v1/node")
        .and_raise(HttpTransport::ApiError.new(500, "Internal Server Error"))

      expect(provisioner.healthy?).to be false
    end
  end

  describe "#create!" do
    before do
      TrinoEngineConfig.instance.update!(topology: "cluster", worker_replicas: 3,
                                         coordinator_cpu: "2", coordinator_memory: "2Gi",
                                         worker_cpu: "1", worker_memory: "2Gi")
      allow(k8s).to receive(:apply_spec)
      allow(worker_k8s).to receive(:apply_spec)
    end

    it "scales coordinator and workers with the configured resources" do
      provisioner.create!

      expect(k8s).to have_received(:apply_spec).with(
        replicas: 1, cpu: "2", memory: "2Gi", env: { "TRINO_INCLUDE_COORDINATOR" => "false" }
      )
      expect(worker_k8s).to have_received(:apply_spec).with(
        replicas: 3, cpu: "1", memory: "2Gi"
      )
    end

    it "runs the coordinator as a task node in single topology and leaves workers alone" do
      TrinoEngineConfig.instance.update!(topology: "single")

      provisioner.create!

      expect(k8s).to have_received(:apply_spec).with(
        replicas: 1, cpu: "2", memory: "2Gi", env: { "TRINO_INCLUDE_COORDINATOR" => "true" }
      )
      expect(worker_k8s).not_to have_received(:apply_spec)
    end
  end

  describe "#destroy!" do
    it "scales both coordinator and workers to zero" do
      allow(k8s).to receive(:scale)
      allow(worker_k8s).to receive(:scale)

      provisioner.destroy!

      expect(k8s).to have_received(:scale).with(0)
      expect(worker_k8s).to have_received(:scale).with(0)
    end
  end

  describe "#rollout_complete?" do
    it "requires the coordinator and, in cluster mode, the workers" do
      TrinoEngineConfig.instance.update!(topology: "cluster")
      allow(k8s).to receive(:ready?).and_return(true)
      allow(worker_k8s).to receive(:ready?).and_return(true)

      expect(provisioner.rollout_complete?).to be(true)
      expect(worker_k8s).to have_received(:ready?)
    end

    it "only requires the coordinator in single mode" do
      TrinoEngineConfig.instance.update!(topology: "single")
      allow(k8s).to receive(:ready?).and_return(true)
      allow(worker_k8s).to receive(:ready?)

      expect(provisioner.rollout_complete?).to be(true)
      expect(worker_k8s).not_to have_received(:ready?)
    end
  end

  describe "Kubernetes failures" do
    # SuperviseEngineStartJob only rescues TrinoProvisioner::Error and
    # Timeout::Error, and ApplicationJob has no generic retry - so an unwrapped
    # Kubeclient error killed the job, skipped MAX_START_ATTEMPTS and left the
    # engine in "starting" until the watchdog gave up minutes later.
    let(:not_found) { Kubeclient::ResourceNotFoundError.new(404, "deployments 'trino-worker' not found", nil) }

    before do
      allow(k8s).to receive(:target).and_return("ldd/trino-coordinator")
      allow(worker_k8s).to receive(:target).and_return("ldd/trino-worker")
    end

    it "wraps a missing coordinator on create! with a pre-provision hint" do
      allow(TrinoEngineConfig).to receive(:instance).and_return(TrinoEngineConfig.new(topology: "single"))
      allow(k8s).to receive(:apply_spec).and_raise(not_found)

      expect { provisioner.create! }
        .to raise_error(TrinoProvisioner::Error, /coordinator .ldd\/trino-coordinator.*pre-created/)
    end

    it "wraps a missing worker on create! with a pre-provision hint" do
      allow(TrinoEngineConfig).to receive(:instance).and_return(TrinoEngineConfig.new(topology: "cluster"))
      allow(k8s).to receive(:apply_spec)
      allow(worker_k8s).to receive(:apply_spec).and_raise(not_found)

      expect { provisioner.create! }
        .to raise_error(TrinoProvisioner::Error, /worker .ldd\/trino-worker.*pre-created/)
    end

    it "tolerates a missing worker Deployment on destroy!" do
      allow(k8s).to receive(:scale)
      allow(worker_k8s).to receive(:scale).and_raise(not_found)

      expect { provisioner.destroy! }.not_to raise_error
      expect(k8s).to have_received(:scale).with(0)
    end
  end
end
