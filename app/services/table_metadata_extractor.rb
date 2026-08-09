# Pulls the full Iceberg REST TableMetadata out of a GetTableResponse payload
# (the `metadata` object, or a top-level table object).
#
# Distinguishes "no data" (nil) from "zero" - the difference is what keeps the
# health score from lying.
class TableMetadataExtractor
  def initialize(metadata)
    @metadata = metadata
  end

  def table_uuid       = @metadata["table-uuid"]
  def storage_location = @metadata["location"]
  def properties       = @metadata["properties"] || {}
  def schemas          = @metadata["schemas"] || []
  def partition_specs  = @metadata["partition-specs"] || []
  def refs             = @metadata["refs"] || {}

  def snapshots = @metadata["snapshots"] || @metadata["snapshot-list"] || []
  def snapshot_count = snapshots.size

  def last_snapshot_at   = snapshot_time(current_snapshot)
  def oldest_snapshot_at = snapshot_time(snapshots.first)

  # nil when the summary does not carry the field - NOT zero.
  def total_records    = summary_int("total-records")
  def total_data_files = summary_int("total-data-files")
  def total_size_bytes = summary_int("total-files-size-in-bytes")
  def position_deletes = summary_int("total-position-deletes")
  def equality_deletes = summary_int("total-equality-deletes")

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

  def current_snapshot
    id = @metadata["current-snapshot-id"] || @metadata["current-snapshot_id"]
    snapshots.find { |s| (s["snapshot-id"] || s["snapshot_id"]) == id } || snapshots.last
  end

  def snapshot_time(snap)
    return nil if snap.nil?

    ms = snap["timestamp-ms"] || snap["timestamp_ms"]
    ms.nil? ? nil : Time.at(ms.to_f / 1000.0)
  end

  def summary_int(key)
    value = current_snapshot&.dig("summary", key)
    value.nil? ? nil : value.to_i
  end
end
