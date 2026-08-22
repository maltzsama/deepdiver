# Runs arbitrary SQL against the ephemeral Trino and returns rows keyed by
# column name. Used by the freshness probe (SELECT MAX of a watermark, distinct
# recent partitions); the maintenance path keeps using TrinoRestClient.
class TrinoClient
  # Raised when Trino rejects a statement or fails to finish a query.
  class Error < StandardError; end

  POLL_INTERVAL = ENV.fetch("TRINO_QUERY_POLL_SECONDS", "1").to_i # seconds between nextUri calls
  MAX_POLL_SECONDS = ENV.fetch("TRINO_QUERY_MAX_SECONDS", "3600").to_i

  # Creates the client with an endpoint and optional default catalog.
  #
  # @param endpoint [String] the Trino coordinator URL
  # @param catalog_name [String, nil] the default catalog header value
  # @param transport [HttpTransport] injectable transport (tests)
  # @param query_timeout [Integer, nil] per-query timeout in seconds (nil = MAX_POLL_SECONDS)
  def initialize(endpoint: ENV.fetch("TRINO_URL"), catalog_name: nil, transport: HttpTransport.new,
                 query_timeout: nil)
    @endpoint = endpoint
    @catalog_name = catalog_name
    @transport = transport
    @query_timeout = query_timeout
  end

  # Runs arbitrary SQL and returns the rows as hashes keyed by column name.
  def run_with_names(sql)
    poll(sql, limit: nil)
  end

  # Runs SQL and returns the value of a single column in the first row.
  # Stops paginating after the first row — no need to drain every page.
  #
  # @param sql [String] the query
  # @param column [String] the column to read
  # @return [Object, nil] the first row's value
  def query_scalar(sql, column)
    rows = poll(sql, limit: 1)
    rows.first&.fetch(column, nil)
  end

  # Runs SQL and returns the values of a column across all rows.
  # For small result sets (DISTINCT + LIMIT) this drains all pages;
  # for a single value prefer query_scalar.
  #
  # @param sql [String] the query
  # @param column [String] the column to read
  # @return [Array] the column values
  def query_column(sql, column)
    poll(sql, limit: nil).filter_map { |row| row[column] }
  end

  private

  # Submits a statement and returns the initial response, raising on rejection.
  #
  # @param sql [String] the query
  # @return [Hash] the Trino statement response
  def statement(sql)
    @transport.post(uri("/v1/statement"), body: sql, headers: headers)
  rescue HttpTransport::ApiError => e
    raise Error, "Trino statement rejected: #{e.message}"
  end

  # Follows nextUri until the query finishes, raising on error or timeout.
  #
  # Trino streams rows page by page: the data for a small query usually lands
  # on an INTERMEDIATE page and the final page carries only columns. Rows are
  # accumulated across pages until +limit+ rows are collected (nil = no limit).
  #
  # @param sql [String] the SQL statement
  # @param limit [Integer, nil] stop paginating after this many rows (nil = all)
  # @return [Array<Hash>] rows keyed by column name
  def poll(sql, limit: nil)
    deadline = Time.current + (@query_timeout || MAX_POLL_SECONDS)
    current = statement(sql)
    rows = []

    loop do
      if current["error"]
        raise Error, (current["error"]["message"] || "Trino query failed")
      end

      rows.concat(rows_with_names(current))

      return rows unless current["nextUri"]
      return rows if limit && rows.size >= limit

      timeout = @query_timeout || MAX_POLL_SECONDS
      raise Error, "Trino query exceeded #{timeout}s without finishing" if Time.current > deadline

      sleep POLL_INTERVAL
      current = @transport.get(uri(current["nextUri"]), headers: headers)
    end
  end

  # Converts Trino data rows into hashes keyed by column name.
  #
  # @param response [Hash] a Trino response with columns and data
  # @return [Array<Hash>] the rows
  def rows_with_names(response)
    names = (response["columns"] || []).map { |c| c["name"] }
    (response["data"] || []).map { |row| names.zip(row).to_h }
  end

  # Resolves a path or absolute URL against the endpoint.
  #
  # @param path [String] the request path or URL
  # @return [String] the absolute URL
  def uri(path)
    path.start_with?("http") ? path : URI.join("#{@endpoint}/", path).to_s
  end

  # The Trino request headers, including the catalog when configured.
  #
  # @return [Hash] the headers
  def headers
    h = { "X-Trino-User" => "lakedeepdiver", "X-Trino-Source" => "lakedeepdiver-freshness" }
    h["X-Trino-Catalog"] = @catalog_name if @catalog_name.present?
    h
  end
end
