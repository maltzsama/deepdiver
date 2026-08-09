require "test_helper"

class StubTrinoTransport
  def initialize(responses)
    @responses = responses
  end

  def post(uri, body:, headers: {})
    @responses.fetch(uri)
  end

  def get(uri, headers: {})
    @responses.fetch(uri)
  end
end

class TrinoRestClientTest < ActiveSupport::TestCase
  ENDPOINT = "http://trino:8080"

  def client(transport)
    TrinoRestClient.new(endpoint: ENDPOINT, transport: transport)
  end

  test "polls nextUri until the final response and returns compact metrics" do
    transport = StubTrinoTransport.new(
      "#{ENDPOINT}/v1/statement" => { "nextUri" => "#{ENDPOINT}/v1/statement/queue/a" },
      "#{ENDPOINT}/v1/statement/queue/a" => { "nextUri" => "#{ENDPOINT}/v1/statement/queue/b" },
      "#{ENDPOINT}/v1/statement/queue/b" => {
        "columns" => [ { "name" => "success" }, { "name" => "written" } ],
        "data" => [ [ "true", "42" ] ],
        "stats" => { "elapsedTimeMillis" => 12, "processedBytes" => 1024 }
      }
    )

    metrics = client(transport).execute("ALTER TABLE ... EXECUTE optimize", execution_id: 7)

    assert_equal 1, metrics["rows"]
    assert_equal %w[success written], metrics["columns"]
    assert_equal 12, metrics.dig("stats", "elapsedTimeMillis")
    assert_equal 7, metrics["execution_history_id"]
  end

  test "raises a commit conflict when the engine reports one" do
    transport = StubTrinoTransport.new(
      "#{ENDPOINT}/v1/statement" => { "error" => { "message" => "Concurrent commits are not allowed" } }
    )

    assert_raises(TrinoRuntime::CommitConflict) { client(transport).execute("SELECT 1", execution_id: 7) }
  end

  test "raises a plain error for any other failure" do
    transport = StubTrinoTransport.new(
      "#{ENDPOINT}/v1/statement" => { "error" => { "message" => "Syntax error" } }
    )

    error = assert_raises(TrinoRestClient::Error) { client(transport).execute("BROKEN", execution_id: 7) }
    assert_match(/Syntax error/, error.message)
  end
end
