# Pulls the full Iceberg REST TableMetadata out of a GetTableResponse payload
# (the `metadata` object, or a top-level table object).
#
# Distinguishes "no data" (nil) from "zero" - the difference is what keeps the
# health score from lying.
class TableMetadataExtractor
  # Creates an extractor around a TableMetadata hash.
  #
  # @param metadata [Hash] the raw TableMetadata payload
  def initialize(metadata)
    @metadata = metadata
  end

  # Rebuilds an extractor from the metadata already persisted on the table
  # (CR-42 columns), without calling the catalog again. Summary fields come
  # straight from the snapshot the sync chose as current.
  def self.from_persisted(table)
    summary = {}
    summary["total-records"] = table.total_records if table.total_records
    summary["total-data-files"] = table.total_data_files if table.total_data_files
    summary["total-files-size-in-bytes"] = table.total_size_bytes if table.total_size_bytes
    summary["total-position-deletes"] = table.position_deletes if table.position_deletes
    summary["total-equality-deletes"] = table.equality_deletes if table.equality_deletes

    count = table.snapshot_count || 0
    snapshots = Array.new(count) { {} }
    snapshots.last["summary"] = summary if snapshots.any?

    new(
      "properties" => table.properties_json || {},
      "snapshots" => snapshots,
      "current-snapshot-id" => 0
    )
  end

  # The table's UUID.
  #
  # @return [String, nil] the table-uuid
  def table_uuid       = @metadata["table-uuid"]
  # The table's storage location.
  #
  # @return [String, nil] the location
  def storage_location = @metadata["location"]
  # The table's properties map.
  #
  # @return [Hash] the properties
  def properties       = @metadata["properties"] || {}
  # The table's schema list.
  #
  # @return [Array] the schemas
  def schemas          = @metadata["schemas"] || []
  # The table's partition spec list.
  #
  # @return [Array] the partition specs
  def partition_specs  = @metadata["partition-specs"] || []
  # The table's named refs map.
  #
  # @return [Hash] the refs
  def refs             = @metadata["refs"] || {}

  # The table's snapshot list.
  #
  # @return [Array] the snapshots
  def snapshots = @metadata["snapshots"] || @metadata["snapshot-list"] || []
  # The number of snapshots.
  #
  # @return [Integer] the snapshot count
  def snapshot_count = snapshots.size

  # Timestamp of the current (last) snapshot.
  #
  # @return [Time, nil] the snapshot time
  def last_snapshot_at   = snapshot_time(current_snapshot)
  # Timestamp of the oldest snapshot.
  #
  # @return [Time, nil] the snapshot time
  def oldest_snapshot_at = snapshot_time(snapshots.first)

  # nil when the summary does not carry the field - NOT zero.
  def total_records    = summary_int("total-records")
  # Total data-file count, nil when absent - NOT zero.
  #
  # @return [Integer, nil] the count
  def total_data_files = summary_int("total-data-files")
  # Total size of data files in bytes, nil when absent - NOT zero.
  #
  # @return [Integer, nil] the size
  def total_size_bytes = summary_int("total-files-size-in-bytes")
  # Total position-delete count, nil when absent - NOT zero.
  #
  # @return [Integer, nil] the count
  def position_deletes = summary_int("total-position-deletes")
  # Total equality-delete count, nil when absent - NOT zero.
  #
  # @return [Integer, nil] the count
  def equality_deletes = summary_int("total-equality-deletes")

  # Average data-file size in bytes, nil when there are no files.
  #
  # @return [Integer, nil] the average size
  def average_file_size
    return nil if total_size_bytes.nil? || total_data_files.nil? || total_data_files.zero?

    total_size_bytes / total_data_files
  end

  # Series for the record-distribution chart.
  def records_series(limit: 30)
    snapshots.last(limit).filter_map do |snap|
      timestamp = snapshot_time(snap)
      next if timestamp.nil?

      { at: timestamp, records: snap.dig("summary", "total-records")&.to_i,
        operation: snap.dig("summary", "operation") }
    end
  end

  private

  # The snapshot the table currently points at, or the last one.
  #
  # @return [Hash, nil] the snapshot
  def current_snapshot
    id = @metadata["current-snapshot-id"] || @metadata["current-snapshot_id"]
    snapshots.find { |s| (s["snapshot-id"] || s["snapshot_id"]) == id } || snapshots.last
  end

  # Converts a snapshot's timestamp to a UTC Time.
  #
  # @param snap [Hash, nil] the snapshot
  # @return [Time, nil] the timestamp
  def snapshot_time(snap)
    return nil if snap.nil?

    ms = snap["timestamp-ms"] || snap["timestamp_ms"]
    ms.nil? ? nil : Time.at(ms.to_f / 1000.0)
  end

  # Reads an integer from the current snapshot's summary, nil when absent.
  #
  # @param key [String] the summary key
  # @return [Integer, nil] the value
  def summary_int(key)
    value = current_snapshot&.dig("summary", key)
    value.nil? ? nil : value.to_i
  end
end
