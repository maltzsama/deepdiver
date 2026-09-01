# Scores 0-100 from what maintenance actually fixes.
#
# Each component returns a value, its contribution and the operation that
# resolves it - the UI shows this, so the number stops being opaque.
#
# A component without data is EXCLUDED and the total is normalised over the
# available weights. Missing data never becomes a penalty.
class HealthEvaluator
  DEFAULT_TARGET_FILE_SIZE = 128 * 1024 * 1024
  HEALTHY_BOUNDARY = 70
  WARNING_BOUNDARY = 40
  # Steady-state horizon for the snapshot budget. Deliberately fixed (not the
  # plan's retention_threshold) so raising retention cannot improve the score.
  REFERENCE_SNAPSHOT_WINDOW_DAYS = 7

  WEIGHTS = {
    fragmentation:    40,
    snapshot_buildup: 30,
    delete_overhead: 20,
    manifest_buildup: 10
  }.freeze

  # Convenience entry point that evaluates health from an extractor.
  #
  # @param extractor [TableMetadataExtractor] the table metadata source
  # @param plan [MaintenancePlan, nil] the maintenance plan for context
  # @param now [Time] the reference clock
  # @param manifest_count [Integer, nil] manifest count from Trino (post-maintenance)
  # @return [Hash] the health score, status, components and coverage
  def self.evaluate(extractor, plan: nil, now: Time.current, manifest_count: nil)
    new(extractor, plan: plan, now: now, manifest_count: manifest_count).call
  end

  # Creates the evaluator with the extractor, plan and clock.
  #
  # @param extractor [TableMetadataExtractor] the table metadata source
  # @param plan [MaintenancePlan, nil] the maintenance plan for context
  # @param now [Time] the reference clock
  # @param manifest_count [Integer, nil] manifest count from Trino (post-maintenance)
  def initialize(extractor, plan: nil, now: Time.current, manifest_count: nil)
    @extractor = extractor
    @plan = plan
    @now = now
    @manifest_count = manifest_count
  end

  # Computes the weighted health score and status from the available components.
  #
  # @return [Hash] the score, status, components and coverage
  def call
    components = {
      fragmentation:    fragmentation,
      snapshot_buildup: snapshot_buildup,
      delete_overhead:  delete_overhead,
      manifest_buildup: manifest_buildup
    }

    available = components.reject { |_key, value| value.nil? }
    return { score: nil, status: :unknown, components: components } if available.empty?

    total_weight = available.keys.sum { |key| WEIGHTS[key] }
    earned = available.sum { |key, ratio| WEIGHTS[key] * ratio }
    score = ((earned / total_weight.to_f) * 100).round

    { score: score, status: status_for(score), components: components,
      coverage: (total_weight / WEIGHTS.values.sum.to_f * 100).round }
  end

  private

  # Each component returns 0.0 (worst) to 1.0 (best), or nil when there is no
  # data.
  def fragmentation
    average = @extractor.average_file_size
    return nil if average.nil?

    (average.to_f / target_file_size).clamp(0.0, 1.0)
  end

  # Scores the snapshot count against the expected budget.
  #
  # The budget is derived from the table's REAL commit rate (snapshots per day,
  # observed from oldest → latest snapshot) times the retention window — not a
  # fixed ~10/day assumption. A busy table that commits hourly no longer scores
  # 0.0 forever right after a successful expire, and raising retention no longer
  # makes the table look healthier (the budget scales with what the plan
  # actually keeps).
  #
  # @return [Float, nil] 0.0-1.0, or nil when there is no snapshot data
  def snapshot_buildup
    count = @extractor.snapshot_count
    return nil if count.nil? || count.zero?

    budget = expected_snapshot_budget
    (1.0 - ((count - budget).to_f / budget)).clamp(0.0, 1.0)
  end

  # Scores the delete-file overhead relative to the record count.
  #
  # @return [Float, nil] 0.0-1.0, or nil when there is no delete data
  def delete_overhead
    records = @extractor.total_records
    deletes = [ @extractor.position_deletes, @extractor.equality_deletes ].compact.sum
    return nil if records.nil? || records.zero? || (@extractor.position_deletes.nil? && @extractor.equality_deletes.nil?)

    (1.0 - (deletes.to_f / records) * 10).clamp(0.0, 1.0)
  end

  # Scores the manifest count against the expected budget.
  #
  # The budget is proportional to the snapshot budget (manifests tend to
  # accumulate alongside snapshots). When manifest_count is nil (engine
  # was down / never measured), the component is excluded.
  #
  # @return [Float, nil] 0.0-1.0, or nil when there is no manifest data
  def manifest_buildup
    count = @manifest_count
    return nil if count.nil?

    budget = expected_manifest_budget
    (1.0 - ((count - budget).to_f / budget)).clamp(0.0, 1.0)
  end

  # The configured target file size, falling back to the default.
  #
  # @return [Integer] the target file size in bytes
  def target_file_size
    @extractor.properties["write.target-file-size-bytes"]&.to_i.presence || DEFAULT_TARGET_FILE_SIZE
  end

  # The expected snapshot budget derived from the table's observed commit rate
  # over a FIXED reference window. Retention is deliberately NOT in the budget:
  # scaling it by the configurable retention_threshold meant raising retention
  # made a table look healthier (the metric's meaning inverted). The reference
  # window is the same steady-state horizon the plan defaults to, so a table
  # that expires correctly sits at ~budget regardless of how the operator tunes
  # retention.
  #
  # @return [Integer] the snapshot budget
  def expected_snapshot_budget
    rate = observed_snapshots_per_day || 10
    [ rate * REFERENCE_SNAPSHOT_WINDOW_DAYS, 10 ].max.round
  end

  # The table's observed snapshot commit rate, derived from the oldest and
  # latest snapshot timestamps. Returns nil when either end is unknown.
  #
  # @return [Float, nil] snapshots per day
  def observed_snapshots_per_day
    oldest = @extractor.oldest_snapshot_at
    latest = @extractor.last_snapshot_at
    count  = @extractor.snapshot_count
    return nil if oldest.nil? || latest.nil? || count.nil? || count.zero?

    span_days = (latest - oldest) / 1.day
    return nil if span_days <= 0

    count.to_f / span_days
  end

  # The expected manifest budget: proportional to the snapshot budget since
  # manifests accumulate alongside snapshots. Half the snapshot budget is a
  # reasonable starting point — an optimize that compacts manifests should
  # bring the count within this range.
  #
  # @return [Integer] the manifest budget
  def expected_manifest_budget
    [ expected_snapshot_budget / 2, 5 ].max
  end

  # Maps a score to a health status.
  #
  # @param score [Integer] the 0-100 score
  # @return [Symbol] :healthy, :warning or :critical
  def status_for(score)
    return :healthy if score >= HEALTHY_BOUNDARY
    return :warning if score >= WARNING_BOUNDARY

    :critical
  end
end
