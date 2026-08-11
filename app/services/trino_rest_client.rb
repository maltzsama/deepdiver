# Trino REST client (POST /v1/statement + poll of nextUri). Returns a compact
# metrics hash for execution_histories.metrics. Commit conflicts raised by the
# engine are surfaced as TrinoRuntime::CommitConflict so the retry machine can
# act on them.
class TrinoRestClient
  # Raised when Trino rejects a statement or fails to finish.
  class Error < StandardError; end

  COMMIT_CONFLICT_PATTERN = /(?i)\bcommit(?:s|ed)?\s+(?:concurrent|conflict)\b|\bconcurrent\s+(?:commits?|modification)\b/

  POLL_INTERVAL = ENV.fetch("TRINO_MAINT_POLL_SECONDS", "1").to_i # seconds between nextUri calls
  MAX_POLL_SECONDS = ENV.fetch("TRINO_MAINT_MAX_SECONDS", "21600").to_i

  # Creates the client with an endpoint and injectable transport.
  #
  # @param endpoint [String] the Trino coordinator URL
  # @param transport [HttpTransport] the HTTP transport
  def initialize(endpoint:, transport: HttpTransport.new)
    @endpoint = endpoint
    @transport = transport
  end

  # Executes SQL against Trino and polls until it finishes.
  #
  # @param sql [String] the query
  # @param execution_id [Integer] the execution id for tracking
  # @param execution [ExecutionHistory, nil] the execution for heartbeats
  # @return [Hash] the metrics payload
  def execute(sql, execution_id:, execution: nil)
    first = statement(sql, execution_id: execution_id)
    poll(first, execution_id: execution_id, execution: execution).merge("execution_history_id" => execution_id)
  end

  private

  # Submits a statement and returns the initial response, raising on rejection.
  #
  # @param sql [String] the query
  # @param execution_id [Integer] the execution id for headers
  # @return [Hash] the Trino response
  def statement(sql, execution_id:)
    @transport.post(uri("/v1/statement"), body: { "query" => sql }.to_json,
                    headers: headers(execution_id))
  rescue HttpTransport::ApiError => e
    raise Error, "Trino statement rejected: #{e.message}"
  end

  # Follows nextUri until the query finishes, touching heartbeats along the way.
  #
  # @param response [Hash] the initial statement response
  # @param execution_id [Integer] the execution id for tracking
  # @param execution [ExecutionHistory, nil] the execution to heartbeat
  # @return [Hash] the final response
  def poll(response, execution_id:, execution: nil)
    deadline = Time.current + MAX_POLL_SECONDS
    current = response

    loop do
      return finish(current) if current["error"]
      return finish(current) unless current["nextUri"]

      if Time.current > deadline
        raise Error, "Trino query exceeded #{MAX_POLL_SECONDS}s without finishing"
      end

      # Proof of life: while the poll is happening, the execution is alive.
      # Without this there is no way to tell "long query" from "worker died".
      execution&.touch(:last_heartbeat_at)

      sleep POLL_INTERVAL
      current = @transport.get(uri(current["nextUri"]), headers: headers(execution_id))
    end
  end

  # Turns a final response into metrics, raising on errors or conflicts.
  #
  # @param response [Hash] the final Trino response
  # @return [Hash] the metrics payload
  def finish(response)
    raise commit_conflict(response) if conflict?(response)

    raise Error, error_message(response) if response["error"]

    {
      "columns" => columns(response),
      "rows" => rows(response).size,
      "stats" => (response["stats"] || {}).slice("elapsedTimeMillis", "processedBytes", "physicalWrittenBytes")
    }.compact
  end

  # Whether the response error indicates a commit conflict.
  #
  # @param response [Hash] the Trino response
  # @return [Boolean] true for a commit conflict
  def conflict?(response)
    error = response["error"]
    return false unless error

    message = error["message"] || ""
    message.match?(COMMIT_CONFLICT_PATTERN)
  end

  # Builds a CommitConflict exception from the response error.
  #
  # @param response [Hash] the Trino response
  # @return [TrinoRuntime::CommitConflict] the exception
  def commit_conflict(response)
    TrinoRuntime::CommitConflict.new(error_message(response))
  end

  # Extracts a human-readable error message from a Trino response.
  #
  # @param response [Hash] the Trino response
  # @return [String] the message
  def error_message(response)
    error = response["error"] || {}
    error["message"] || error["errorName"] || "Trino query failed"
  end

  # Extracts the column names from a Trino response.
  #
  # @param response [Hash] the Trino response
  # @return [Array<String>] the column names
  def columns(response)
    (response["columns"] || []).map { |c| c["name"] }
  end

  # Extracts the data rows from a Trino response.
  #
  # @param response [Hash] the Trino response
  # @return [Array] the rows
  def rows(response)
    response["data"] || []
  end

  # Resolves a path or absolute URL against the endpoint.
  #
  # @param path [String] the request path or URL
  # @return [String] the absolute URL
  def uri(path)
    path.start_with?("http") ? path : URI.join("#{@endpoint}/", path).to_s
  end

  # The Trino headers, tagging the source with the execution id.
  #
  # @param execution_id [Integer] the execution id
  # @return [Hash] the headers
  def headers(execution_id)
    {
      "X-Trino-User" => "lakedeepdiver",
      "X-Trino-Source" => "lakedeepdiver-maintenance",
      "X-Trino-Client-Info" => "lakedeepdiver/#{execution_id}"
    }
  end
end
