require "rails_helper"

RSpec.describe TrinoRestClient do
  let(:transport) { instance_double(HttpTransport) }
  let(:client) { described_class.new(endpoint: "http://trino", transport: transport) }

  it "returns the query id in the metrics" do
    allow(transport).to receive(:post).and_return(
      "id" => "20260813_000001_00000_abcde",
      "nextUri" => "http://trino/next",
      "stats" => {}
    )
    allow(transport).to receive(:get).and_return(
      "columns" => [], "data" => [],
      "stats" => { "elapsedTimeMillis" => 42, "processedBytes" => 10, "physicalWrittenBytes" => 5 }
    )

    result = client.execute("SELECT 1", execution_id: 1)

    expect(result["query_id"]).to eq("20260813_000001_00000_abcde")
    expect(result["stats"]["elapsedTimeMillis"]).to eq(42)
  end

  it "stamps the step with the query id as soon as the statement is accepted" do
    step = instance_double(ExecutionStep, metrics: {})
    allow(step).to receive(:update_column)

    allow(transport).to receive(:post).and_return(
      "id" => "qid", "nextUri" => "http://trino/next", "stats" => {}
    )
    allow(transport).to receive(:get).and_return("columns" => [], "data" => [], "stats" => {})

    client.execute("SELECT 1", execution_id: 1, step: step)

    expect(step).to have_received(:update_column).with(:trino_query_id, "qid")
  end

  it "records live progress onto the step while polling" do
    step = instance_double(ExecutionStep, metrics: {})
    allow(step).to receive(:update_column)

    allow(transport).to receive(:post).and_return(
      "id" => "qid", "nextUri" => "http://trino/next", "stats" => {}
    )
    allow(transport).to receive(:get).and_return(
      {
        "nextUri" => "http://trino/more",
        "stats" => { "state" => "RUNNING", "processedRows" => 99, "processedBytes" => 1234 }
      },
      {
        "columns" => [], "data" => [], "stats" => { "state" => "FINISHED" }
      }
    )

    client.execute("SELECT 1", execution_id: 1, step: step)

    expect(step).to have_received(:update_column).with(
      :metrics, hash_including("progress" => hash_including("processed_rows" => 99))
    ).at_least(:once)
  end
end
