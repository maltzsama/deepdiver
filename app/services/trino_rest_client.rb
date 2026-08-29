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
  # @param step [ExecutionStep, nil] the step being run, for query id/progress
  # @return [Hash] the metrics payload
  def execute(sql, execution_id:, execution: nil, step: nil)
    first = statement(sql, execution_id: execution_id)
    capture_query_id(step, first)
    poll(first, execution_id: execution_id, execution: execution, step: step)
      .merge("execution_history_id" => execution_id, "query_id" => first["id"])
  end

  private

  # Submits a statement and returns the initial response, raising on rejection.
  #
  # Trino's /v1/statement expects the RAW SQL body (with X-Trino-User headers),
  # not a {"query": "..."} JSON envelope. Sending the envelope makes Trino try
  # to parse the leading '{' as SQL.
  #
  # @param sql [String] the query
  # @param execution_id [Integer] the execution id for headers
  # @return [Hash] the Trino response
  def statement(sql, execution_id:)
    @transport.post(uri("/v1/statement"), body: sql,
                    headers: headers(execution_id))
  rescue HttpTransport::ApiError => e
    raise Error, "Trino statement rejected: #{e.message}"
  end

  # Follows nextUri until the query finishes, touching heartbeats and persisting
  # progress along the way.
  #
  # @param response [Hash] the initial statement response
  # @param execution_id [Integer] the execution id for tracking
  # @param execution [ExecutionHistory, nil] the execution to heartbeat
  # @param step [ExecutionStep, nil] the step to record progress on
  # @return [Hash] the final response
  def poll(response, execution_id:, execution: nil, step: nil)
    deadline = Time.current + MAX_POLL_SECONDS
    current = response
    # Trino streams rows page by page and the final page usually carries only
    # columns, so counting them off the last response reported ~0 regardless of
    # what the statement returned.
    row_count = 0

    loop do
      row_count += rows(current).size

      return finish(current, row_count) if current["error"]
      return finish(current, row_count) unless current["nextUri"]

      if Time.current > deadline
        raise Error, "Trino query exceeded #{MAX_POLL_SECONDS}s without finishing"
      end

      # Proof of life: while the poll is happening, the execution is alive.
      # Without this there is no way to tell "long query" from "worker died".
      execution&.touch(:last_heartbeat_at)

      record_progress(step, current)

      sleep POLL_INTERVAL
      current = @transport.get(uri(current["nextUri"]), headers: headers(execution_id))
    end
  end

  # Stamps the step with the Trino query id as soon as the statement is accepted,
  # so the query is traceable while it is still running.
  #
  # @param step [ExecutionStep, nil] the step to stamp
  # @param response [Hash] the initial statement response
  def capture_query_id(step, response)
    step&.update_column(:trino_query_id, response["id"])
  end

  # Persists live progress (rows, bytes, state) onto the step as the query runs,
  # so the activity screen can show what the query is doing right now.
  #
  # @param step [ExecutionStep, nil] the step to update
  # @param response [Hash] the current poll response
  def record_progress(step, response)
    return if step.nil?

    stats = response["stats"] || {}
    progress = {
      "state" => stats["state"],
      "processed_rows" => stats["processedRows"],
      "processed_bytes" => stats["processedBytes"]
    }.compact
    return if progress.empty?

    step.update_column(:metrics, (step.metrics || {}).merge("progress" => progress))
  end

  # Turns a final response into metrics, raising on errors or conflicts.
  #
  # @param response [Hash] the final Trino response
  # @param row_count [Integer] rows accumulated across every page
  # @return [Hash] the metrics payload
  def finish(response, row_count)
    raise commit_conflict(response) if conflict?(response)

    raise Error, error_message(response) if response["error"]

    {
      "columns" => columns(response),
      "rows" => row_count,
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

  # Extracts a human-readable error message from a Trino response, including
  # the nested failureInfo cause chain so the top-level message (often just
  # "Cannot obtain metadata") is followed by the actual root cause.
  #
  # @param response [Hash] the Trino response
  # @return [String] the message
  def error_message(response)
    error = response["error"] || {}
    top = error["message"] || error["errorName"] || "Trino query failed"

    causes = failure_messages(error["failureInfo"])
    causes = causes.reject { |m| m.blank? || m == top }

    ([ top ] + causes).join(" → ")
  end

  # Recursively collects the message of a failureInfo and its nested causes.
  #
  # @param failure_info [Hash, nil] the failureInfo node
  # @param acc [Array<String>] the accumulated messages
  # @return [Array<String>] the collected messages
  def failure_messages(failure_info, acc = [])
    return acc if failure_info.nil?

    acc << failure_info["message"] if failure_info["message"].present?
    failure_messages(failure_info["cause"], acc)
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
      "X-Trino-User" => "deepdiver",
      "X-Trino-Source" => "deepdiver-maintenance",
      "X-Trino-Client-Info" => "deepdiver/#{execution_id}"
    }
  end
end
