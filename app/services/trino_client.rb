# Runs arbitrary SQL against the ephemeral Trino and returns rows keyed by
# column name. Used by the freshness probe (SELECT MAX of a watermark, distinct
# recent partitions); the maintenance path keeps using TrinoRestClient.
class TrinoClient
  class Error < StandardError; end

  POLL_INTERVAL = 1 # second between nextUri calls
  MAX_POLL_SECONDS = 60 * 60

  def initialize(endpoint: ENV.fetch("TRINO_URL"), catalog_name: nil)
    @endpoint = endpoint
    @catalog_name = catalog_name
    @transport = HttpTransport.new
  end

  # Runs arbitrary SQL and returns the rows as hashes keyed by column name.
  def run_with_names(sql)
    poll(statement(sql))
  end

  def query_scalar(sql, column)
    rows = run_with_names(sql)
    rows.first&.fetch(column, nil)
  end

  def query_column(sql, column)
    run_with_names(sql).filter_map { |row| row[column] }
  end

  private

  def statement(sql)
    @transport.post(uri("/v1/statement"), body: { "query" => sql }.to_json, headers: headers)
  rescue HttpTransport::ApiError => e
    raise Error, "Trino statement rejected: #{e.message}"
  end

  def poll(response)
    deadline = Time.current + MAX_POLL_SECONDS
    current = response

    loop do
      if current["error"]
        raise Error, (current["error"]["message"] || "Trino query failed")
      end

      return rows_with_names(current) unless current["nextUri"]

      raise Error, "Trino query exceeded #{MAX_POLL_SECONDS}s without finishing" if Time.current > deadline

      sleep POLL_INTERVAL
      current = @transport.get(uri(current["nextUri"]), headers: headers)
    end
  end

  def rows_with_names(response)
    names = (response["columns"] || []).map { |c| c["name"] }
    (response["data"] || []).map { |row| names.zip(row).to_h }
  end

  def uri(path)
    path.start_with?("http") ? path : URI.join("#{@endpoint}/", path).to_s
  end

  def headers
    h = { "X-Trino-User" => "lakedeepdiver", "X-Trino-Source" => "lakedeepdiver-freshness" }
    h["X-Trino-Catalog"] = @catalog_name if @catalog_name.present?
    h
  end
end
