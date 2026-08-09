# Measures the freshness of ONE table: two queries, pruned by partition.
#
# Query 1 returns the N most recent partitions. No arithmetic on the value -
# the partition is an int in the 20260807 format, and 20260801 - 1 would give
# 20260800, which does not exist. Every first of the month would become a false
# alarm.
#
# Query 2 takes the MAX of the watermark column inside those partitions. Trino
# usually answers from the manifest upper_bound, without touching Parquet.
class FreshnessProbe
  class ProbeError < StandardError; end

  Result = Struct.new(:max_timestamp, :delay_seconds, :status, :query_id,
                      :duration_ms, :error_message, keyword_init: true)

  def initialize(sla, client: nil, now: Time.current)
    @sla = sla
    @table = sla.iceberg_table
    @now = now
    @client = client || TrinoClient.new(catalog_name: @table.catalog.trino_catalog_name)
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    raw = fetch_max_timestamp
    return no_data(started) if raw.nil?

    max_ts = normalize(raw)
    delay = (@now - max_ts).to_i

    Result.new(max_timestamp: max_ts, delay_seconds: delay,
               status: classify(delay), duration_ms: elapsed_ms(started))
  rescue StandardError => e
    Result.new(status: "error", error_message: e.message, duration_ms: elapsed_ms(started))
  end

  private

  def fetch_max_timestamp
    partitions = recent_partitions
    return nil if @sla.partition_column.present? && partitions.empty?

    sql = +"SELECT max(#{quote_ident(@sla.timestamp_column)}) AS max_ts FROM #{@table.trino_identifier}"
    if partitions.any?
      sql << " WHERE #{quote_ident(@sla.partition_column)} IN (#{partitions.map { |v| literal(v) }.join(', ')})"
    end

    @client.query_scalar(sql, "max_ts")
  end

  def recent_partitions
    return [] if @sla.partition_column.blank?

    column = quote_ident(@sla.partition_column)
    @client.query_column(<<~SQL.squish, "p")
      SELECT DISTINCT #{column} AS p
      FROM #{@table.trino_identifier}
      WHERE #{column} IS NOT NULL
      ORDER BY p DESC
      LIMIT #{@sla.partition_lookback.to_i}
    SQL
  end

  # Converts the raw value to a UTC Time, per the configured type.
  def normalize(raw)
    case @sla.timestamp_type
    when "timestamp_tz"    then raw.to_time.utc
    when "timestamp_ntz"   then in_source_zone(raw)
    when "epoch_seconds"   then from_epoch(raw.to_i)
    when "epoch_millis"    then from_epoch(raw.to_i / 1_000)
    when "epoch_micros"    then from_epoch(raw.to_i / 1_000_000)
    else raise ProbeError, "unknown timestamp_type: #{@sla.timestamp_type}"
    end
  end

  def in_source_zone(raw)
    naive = raw.is_a?(String) ? Time.parse(raw) : raw.to_time
    ActiveSupport::TimeZone[@sla.source_timezone].local_to_utc(naive)
  end

  # Epoch is UTC by definition. If source_timezone is not UTC, the producer
  # wrote a local wall clock as if it were UTC - compensate.
  def from_epoch(seconds)
    utc = Time.at(seconds).utc
    return utc if @sla.source_timezone == "UTC"

    ActiveSupport::TimeZone[@sla.source_timezone].local_to_utc(utc)
  end

  def classify(delay_seconds)
    budget = @sla.sla_minutes * 60
    return "late"    if delay_seconds > budget
    return "warning" if delay_seconds > budget * (@sla.warning_at_percent / 100.0)

    "ok"
  end

  def no_data(started)
    Result.new(status: "no_data", duration_ms: elapsed_ms(started),
               error_message: "no data in the last #{@sla.partition_lookback} partitions")
  end

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end

  def quote_ident(name) = %("#{name.to_s.gsub('"', '""')}")

  # An int partition is unquoted; a string one is quoted. The type comes from
  # the value Trino itself returned, so there is no configuration to get wrong.
  def literal(value)
    value.is_a?(Numeric) ? value.to_s : "'#{value.to_s.gsub("'", "''")}'"
  end
end
