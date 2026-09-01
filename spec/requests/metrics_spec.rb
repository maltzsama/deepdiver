require "rails_helper"

RSpec.describe "Metrics", type: :request do
  it "exposes the application metrics in the Prometheus text format" do
    get "/metrics"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain; version=0.0.4")
    expect(response.body).to include("# TYPE deepdiver_execution_status gauge")
    expect(response.body).to include("# TYPE deepdiver_trino_engine_status gauge")
    expect(response.body).to include("# TYPE deepdiver_error_events gauge")
    expect(response.body).to include("# TYPE deepdiver_solid_queue_jobs gauge")
  end

  it "does not require authentication" do
    get "/metrics"

    expect(response).to have_http_status(:ok)
  end

  it "derives the execution status gauge from the database" do
    create(:execution_history, status: "failed")
    create(:execution_history, status: "running")

    get "/metrics"

    expect(response.body).to include('deepdiver_execution_status{status="failed"} 1.0')
    expect(response.body).to include('deepdiver_execution_status{status="running"} 1.0')
  end

  it "derives the engine status gauge from the single engine row" do
    TrinoEngineState.instance(status: "down", status_changed_at: Time.current)
                       .update!(status: "up", status_changed_at: Time.current)

    get "/metrics"

    expect(response.body).to include('deepdiver_trino_engine_status{status="up"} 1.0')
    expect(response.body).to include('deepdiver_trino_engine_status{status="down"} 0.0')
  end
end
