# Pulls the liveness signals out of an Iceberg REST TableMetadata payload
# (the `metadata` object of GetTableResponse, or a top-level table object).
class TableMetadataExtractor
  def initialize(metadata)
    @metadata = metadata
  end

  def last_snapshot_at
    snapshot = last_snapshot
    return nil unless snapshot

    timestamp_ms = snapshot["timestamp-ms"] || snapshot["timestamp_ms"]
    Time.at(timestamp_ms.to_f / 1000.0) unless timestamp_ms.nil?
  end

  def snapshot_count
    snapshots.size
  end

  def orphan_file_markers
    orphan = @metadata["orphan-files"] || @metadata["orphan_files"] || []
    orphan.size
  end

  private

  def snapshots
    @metadata["snapshots"] || @metadata["snapshot-list"] || []
  end

  def last_snapshot
    current_id = @metadata["current-snapshot_id"] || @metadata["current-snapshot-id"]
    snapshots.find { |snap| snap["snapshot-id"] == current_id || snap["snapshot_id"] == current_id } || snapshots.last
  end
end
