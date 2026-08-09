require "test_helper"

class HealthEvaluatorTest < ActiveSupport::TestCase
  def extractor(last_at:, snapshots: 0)
    metadata = {}
    metadata["snapshots"] = (1..snapshots).map do |i|
      { "snapshot-id" => i, "timestamp-ms" => (last_at.to_f * 1000).to_i }
    end
    TableMetadataExtractor.new(metadata)
  end

  test "unknown when there is no snapshot info" do
    result = HealthEvaluator.evaluate(TableMetadataExtractor.new({}))
    assert_equal :unknown, result[:status]
    assert_nil result[:score]
  end

  test "healthy for a recent snapshot" do
    result = HealthEvaluator.evaluate(extractor(last_at: 10.minutes.ago, snapshots: 5))
    assert_equal :healthy, result[:status]
    assert_equal 100, result[:score]
  end

  test "warning when the last snapshot is more than a day old" do
    result = HealthEvaluator.evaluate(extractor(last_at: 30.hours.ago, snapshots: 5))
    assert_equal :warning, result[:status]
    assert_equal 60, result[:score]
  end

  test "warning when the last snapshot is a few days old" do
    result = HealthEvaluator.evaluate(extractor(last_at: 3.days.ago, snapshots: 5))
    assert_equal :warning, result[:status]
    assert_equal 40, result[:score]
  end

  test "critical when the last snapshot is over a week old" do
    result = HealthEvaluator.evaluate(extractor(last_at: 10.days.ago, snapshots: 5))
    assert_equal :critical, result[:status]
    assert_equal 20, result[:score]
  end

  test "snapshot count over the floor adds a penalty" do
    result = HealthEvaluator.evaluate(extractor(last_at: 10.minutes.ago, snapshots: 60))
    assert_equal :healthy, result[:status]
    assert_equal 90, result[:score]
  end

  test "heavy snapshot count adds a larger penalty" do
    result = HealthEvaluator.evaluate(extractor(last_at: 10.minutes.ago, snapshots: 300))
    assert_equal 80, result[:score]
  end
end
