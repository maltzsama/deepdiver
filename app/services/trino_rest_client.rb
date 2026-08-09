# Trino REST client (POST /v1/statement + poll of nextUri). Returns a compact
# metrics hash for execution_histories.metrics. Commit conflicts raised by the
# engine are surfaced as TrinoRuntime::CommitConflict so the retry machine can
# act on them.
class TrinoRestClient
  class Error < StandardError; end

  COMMIT_CONFLICT_PATTERN = /(?i)\bcommit(?:s|ed)?\s+(?:concurrent|conflict)\b|\bconcurrent\s+(?:commits?|modification)\b/

  POLL_INTERVAL = 1 # second between nextUri calls
  MAX_POLL_SECONDS = 6 * 60 * 60

  def initialize(endpoint:, transport: HttpTransport.new)
    @endpoint = endpoint
    @transport = transport
  end

  def execute(sql, execution_id:, execution: nil)
    first = statement(sql, execution_id: execution_id)
    poll(first, execution_id: execution_id, execution: execution).merge("execution_history_id" => execution_id)
  end

  private

  def statement(sql, execution_id:)
    @transport.post(uri("/v1/statement"), body: { "query" => sql }.to_json,
                    headers: headers(execution_id))
  rescue HttpTransport::ApiError => e
    raise Error, "Trino statement rejected: #{e.message}"
  end

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

  def finish(response)
    raise commit_conflict(response) if conflict?(response)

    raise Error, error_message(response) if response["error"]

    {
      "columns" => columns(response),
      "rows" => rows(response).size,
      "stats" => (response["stats"] || {}).slice("elapsedTimeMillis", "processedBytes", "physicalWrittenBytes")
    }.compact
  end

  def conflict?(response)
    error = response["error"]
    return false unless error

    message = error["message"] || ""
    message.match?(COMMIT_CONFLICT_PATTERN)
  end

  def commit_conflict(response)
    TrinoRuntime::CommitConflict.new(error_message(response))
  end

  def error_message(response)
    error = response["error"] || {}
    error["message"] || error["errorName"] || "Trino query failed"
  end

  def columns(response)
    (response["columns"] || []).map { |c| c["name"] }
  end

  def rows(response)
    response["data"] || []
  end

  def uri(path)
    path.start_with?("http") ? path : URI.join("#{@endpoint}/", path).to_s
  end

  def headers(execution_id)
    {
      "X-Trino-User" => "lakedeepdiver",
      "X-Trino-Source" => "lakedeepdiver-maintenance",
      "X-Trino-Client-Info" => "lakedeepdiver/#{execution_id}"
    }
  end
end
