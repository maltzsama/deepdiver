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

  it "surfaces the nested failure cause, not just the generic top message" do
    allow(transport).to receive(:post).and_return(
      {
        "error" => {
          "message" => "Cannot obtain metadata",
          "errorName" => "CATALOG_ERROR",
          "failureInfo" => {
            "message" => "Failed to resolve table",
            "cause" => { "message" => "HTTP 404 from catalog" }
          }
        }
      }
    )

    expect { client.execute("ALTER TABLE t EXECUTE optimize", execution_id: 1) }
      .to raise_error(TrinoRestClient::Error, /Cannot obtain metadata → Failed to resolve table → HTTP 404 from catalog/)
  end

  describe "row accounting" do
    it "counts rows across every page, not just the last one" do
      transport = instance_double(HttpTransport)
      client = described_class.new(endpoint: "http://trino", transport: transport)

      # Trino streams rows on intermediate pages; the final page usually carries
      # only columns, so reading the count off it reported ~0 either way.
      first = { "id" => "q1", "data" => [ [ 1 ], [ 2 ] ], "nextUri" => "http://trino/next/1" }
      middle = { "id" => "q1", "data" => [ [ 3 ] ], "nextUri" => "http://trino/next/2" }
      last = { "id" => "q1", "columns" => [ { "name" => "n" } ], "stats" => {} }

      allow(transport).to receive(:post).and_return(first)
      allow(transport).to receive(:get).and_return(middle, last)
      stub_const("#{described_class}::POLL_INTERVAL", 0)

      metrics = client.execute("SELECT 1", execution_id: 1)

      expect(metrics["rows"]).to eq(3)
    end
  end
end
