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
    summary["total-files-size"] = table.total_size_bytes if table.total_size_bytes
    summary["total-position-deletes"] = table.position_deletes if table.position_deletes
    summary["total-equality-deletes"] = table.equality_deletes if table.equality_deletes
    summary["manifest-count"] = table.manifest_count if table.manifest_count

    snapshots = persisted_snapshots(table, summary)

    # No current-snapshot-id: the summary is attached to the LAST entry and
    # #current_snapshot falls back to it. Passing an id (0) made the lookup
    # match a real snapshot that happened to carry that id, so the rebuilt
    # summary was never read and every summary metric came back nil.
    new(
      "properties" => table.properties_json || {},
      "snapshots" => snapshots
    )
  end

  # The snapshot list to score from.
  #
  # Prefers the REAL snapshots persisted by the sync (`snapshots_json` is
  # written straight from `extractor.snapshots`, so every entry keeps its own
  # `timestamp-ms`). The evaluator's snapshot budget counts snapshots inside
  # the reference window, which needs a timestamp on every entry - the previous
  # synthetic list stamped only the two ends, so N-2 entries counted as
  # not-recent, the budget collapsed to its floor and snapshot_buildup was 0.0
  # for every table.
  #
  # Falls back to the synthetic list only when no real snapshots are persisted,
  # so a table whose columns hold measured values still surfaces them.
  #
  # @param table [IcebergTable] the table to read from
  # @param summary [Hash] the summary rebuilt from the persisted columns
  # @return [Array<Hash>] the snapshot list
  def self.synthesized_snapshots(table, summary)
    # A snapshot must carry the summary. With an empty list the summary is
    # discarded and every metric reads back nil even though the columns hold
    # measured values. Pad only when there IS a metric to surface - a table
    # with nothing synced stays unknown rather than scoring from a phantom.
    count = table.snapshot_count || 0
    count = 1 if summary.any? && count.zero?

    # Two entries when both ends of the window are known, so the oldest/latest
    # timestamps cannot alias onto one Hash (see #208).
    if count == 1 && table.oldest_snapshot_at && table.last_data_update &&
       table.oldest_snapshot_at != table.last_data_update
      count = 2
    end
    snapshots = Array.new(count) { {} }
    return snapshots if count.zero?

    snapshots.first["timestamp-ms"] = (table.oldest_snapshot_at.to_f * 1000).to_i if table.oldest_snapshot_at
    snapshots.last["timestamp-ms"] = (table.last_data_update.to_f * 1000).to_i if table.last_data_update
    snapshots.last["summary"] = summary if summary.any?
    snapshots
  end
  private_class_method :synthesized_snapshots

  # The persisted snapshots, with the rebuilt summary attached to the newest
  # entry so the summary-derived metrics stay available.
  #
  # @param table [IcebergTable] the table to read from
  # @param summary [Hash] the summary rebuilt from the persisted columns
  # @return [Array<Hash>] the snapshot list
  def self.persisted_snapshots(table, summary)
    real = table.snapshots_json
    return synthesized_snapshots(table, summary) unless real.is_a?(Array) && real.any?

    # Do not mutate the persisted JSON: the summary is layered onto a copy.
    snapshots = real.map { |snapshot| snapshot.is_a?(Hash) ? snapshot.dup : snapshot }

    # Attach to the LAST entry, which is what #current_snapshot falls back to
    # (there is no current-snapshot-id to match here). Iceberg persists
    # snapshots oldest-first, so the last entry is the newest.
    newest = snapshots.last

    # The persisted columns are the authority for the summary metrics: they
    # carry the Trino enrichment (size, manifest count) that the catalog
    # snapshot summary does not.
    newest["summary"] = (newest["summary"] || {}).merge(summary) if newest.is_a?(Hash) && summary.any?
    snapshots
  end
  private_class_method :persisted_snapshots

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
  # Iceberg writes this key as total-files-size (bytes), not the
  # total-files-size-in-bytes spelling this code historically read — the wrong
  # key made size and average_file_size nil after every catalog sync.
  #
  # @return [Integer, nil] the size
  def total_size_bytes = summary_int("total-files-size")
  # Total position-delete count, nil when absent - NOT zero.
  #
  # @return [Integer, nil] the count
  def position_deletes = summary_int("total-position-deletes")
  # Total equality-delete count, nil when absent - NOT zero.
  #
  # @return [Integer, nil] the count
  def equality_deletes = summary_int("total-equality-deletes")
  # Manifest count, nil when absent - NOT zero. Persisted by the Trino
  # enrichment and carried here so any caller reconstructing state from the
  # database feeds the evaluator the same inputs (see #198).
  #
  # @return [Integer, nil] the count
  def manifest_count = summary_int("manifest-count")

  # Average data-file size in bytes, nil when there are no files.
  #
  # @return [Integer, nil] the average size
  def average_file_size
    return nil if total_size_bytes.nil? || total_data_files.nil? || total_data_files.zero?

    total_size_bytes / total_data_files
  end

  private

  # The snapshot the table currently points at, or the last one.
  #
  # @return [Hash, nil] the snapshot
  def current_snapshot
    id = @metadata["current-snapshot-id"] || @metadata["current-snapshot_id"]
    # Without an id, fall straight through to the newest snapshot. Matching on
    # a nil id found the first entry whose own snapshot-id was also absent -
    # the OLDEST synthetic snapshot - so the summary attached to the newest was
    # never read and every summary metric came back nil.
    return snapshots.last if id.nil?

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
