require "rails_helper"

RSpec.describe "Trino engine config", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:viewer) { create(:user) }

  it "shows the config form to admins" do
    sign_in admin
    TrinoEngineConfig.instance

    get trino_engine_config_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Topology")
  end

  it "updates the config and redirects" do
    sign_in admin
    TrinoEngineConfig.instance

    patch trino_engine_config_path, params: {
      trino_engine_config: {
        topology: "cluster", worker_replicas: 3,
        coordinator_cpu: "4", coordinator_memory: "8Gi",
        worker_cpu: "2", worker_memory: "4Gi"
      }
    }

    expect(response).to redirect_to(trino_engine_config_path)
    config = TrinoEngineConfig.instance
    expect(config.worker_replicas).to eq(3)
    expect(config.coordinator_cpu).to eq("4")
    expect(config.worker_memory).to eq("4Gi")
  end

  it "rejects viewers" do
    sign_in viewer

    get trino_engine_config_path

    expect(response).to redirect_to(root_path)
  end
end
