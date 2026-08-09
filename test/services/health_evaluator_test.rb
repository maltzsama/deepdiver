require "test_helper"

class HealthEvaluatorTest < ActiveSupport::TestCase
  def extractor(metadata = {})
    TableMetadataExtractor.new(metadata)
  end

  def summary_metadata(data_files:, size_bytes:, snapshots:, records: nil,
                       position_deletes: nil, equality_deletes: nil)
    summary = { "total-data-files" => data_files.to_s, "total-files-size-in-bytes" => size_bytes.to_s }
    summary["total-records"] = records.to_s if records
    summary["total-position-deletes"] = position_deletes.to_s if position_deletes
    summary["total-equality-deletes"] = equality_deletes.to_s if equality_deletes
    { "current-snapshot-id" => 1,
      "snapshots" => (1..snapshots).map do |i|
        { "snapshot-id" => i, "timestamp-ms" => 1_700_000_000_000, "summary" => summary }
      end }
  end

  test "unknown when there is no metadata" do
    result = HealthEvaluator.evaluate(extractor({}))
    assert_equal :unknown, result[:status]
    assert_nil result[:score]
  end

  test "healthy for a well compacted cold table" do
    result = HealthEvaluator.evaluate(
      extractor(summary_metadata(data_files: 10, size_bytes: 10 * 128 * 1024 * 1024, snapshots: 5))
    )
    assert_equal :healthy, result[:status]
  end

  test "critical for tiny files and a huge snapshot count" do
    result = HealthEvaluator.evaluate(
      extractor(summary_metadata(data_files: 500, size_bytes: 1000 * 1024 * 1024, snapshots: 900))
    )
    assert_equal :critical, result[:status]
  end
end
