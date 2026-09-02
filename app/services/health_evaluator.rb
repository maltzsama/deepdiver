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
  # The composite is diluted: a severe problem in one dimension is averaged
  # against health in the others (a table 1000x off target can still score
  # 60/warning). The result therefore also carries the worst component, so the
  # UI can lead with it instead of the reassuring average.
  #
  # @return [Hash] the score, status, components, coverage and worst_component
  def call
    components = {
      fragmentation:    fragmentation,
      snapshot_buildup: snapshot_buildup,
      delete_overhead:  delete_overhead,
      manifest_buildup: manifest_buildup
    }

    available = components.reject { |_key, value| value.nil? }
    if available.empty?
      return { score: nil, status: :unknown, components: components,
               worst_component: nil, details: measured_values }
    end

    total_weight = available.keys.sum { |key| WEIGHTS[key] }
    earned = available.sum { |key, ratio| WEIGHTS[key] * ratio }
    score = ((earned / total_weight.to_f) * 100).round

    # The worst available component: the one whose ratio is lowest. This is
    # what actually needs attention — the composite can hide it.
    worst_key, worst_ratio = available.min_by { |_key, ratio| ratio }

    { score: score, status: status_for(score), components: components,
      coverage: (total_weight / WEIGHTS.values.sum.to_f * 100).round,
      worst_component: worst_key, worst_ratio: worst_ratio,
      details: measured_values }
  end

  private

  # The raw numbers behind each ratio, and the budget each was measured
  # against. The evaluator normalises to 0..1 and loses the unit, so a caller
  # that only has the result cannot rebuild "182 snapshots, budget 40" - and
  # the breakdown panel needs exactly that. Emitting them here lets the values
  # be persisted with the score, so the panel renders from a read.
  #
  # @return [Hash] the measured values keyed by component
  def measured_values
    {
      average_file_size: @extractor.average_file_size,
      target_file_size: target_file_size,
      snapshot_count: @extractor.snapshot_count,
      snapshot_budget: snapshot_budget_for_display,
      manifest_count: @manifest_count || @extractor.manifest_count,
      manifest_budget: manifest_budget_for_display,
      total_records: @extractor.total_records,
      delete_count: [ @extractor.position_deletes, @extractor.equality_deletes ].compact.sum
    }
  end

  # The snapshot budget, or nil when there is nothing to measure against.
  # @return [Integer, nil]
  def snapshot_budget_for_display
    return nil if @extractor.snapshot_count.nil? || @extractor.snapshot_count.zero?

    expected_snapshot_budget
  end

  # The manifest budget, or nil when no manifest count is available.
  # @return [Integer, nil]
  def manifest_budget_for_display
    return nil if (@manifest_count || @extractor.manifest_count).nil?

    expected_manifest_budget
  end

  # Each component returns 0.0 (worst) to 1.0 (best), or nil when there is no
  # data.
  def fragmentation
    average = @extractor.average_file_size
    return nil if average.nil? || average <= 0

    # Log scale: a linear ratio collapses every real table into the bottom ~2%
    # of the scale (61 KB -> 0.0009, 819 KB -> 0.012), so the heaviest-weighted
    # component carries no discriminating signal and all tables converge on the
    # same score. Each 10x below target now costs ~1/3 of the component:
    # at target -> 1.0, 10x below -> 0.67, 100x -> 0.33, 1000x or worse -> 0.0.
    decades_below = Math.log10(target_file_size.to_f / average)
    (1.0 - decades_below / 3.0).clamp(0.0, 1.0)
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
  # The count comes from the explicit keyword (fresh-from-Trino path, not yet
  # persisted) or falls back to the extractor, which carries the persisted
  # manifest_count for any caller rebuilding state from the database — so every
  # call site evaluates with the same inputs (see #198).
  #
  # @return [Float, nil] 0.0-1.0, or nil when there is no manifest data
  def manifest_buildup
    count = @manifest_count || @extractor.manifest_count
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

  # The expected snapshot budget: the number of snapshots actually retained in
  # the reference window. Derived from the RECENT snapshots (those newer than
  # the reference window), NOT from count/full_span — the latter cancels
  # algebraically (budget = count*7/span, score = 2 - span/7), so the component
  # measured only window age and a 10 000-snapshot table scored 1.0 (see #207).
  #
  # A table that expires correctly keeps roughly its recent window's worth of
  # snapshots, so count ≈ budget and the score is high; snapshots older than
  # the window push count above budget and the score falls.
  #
  # @return [Integer] the snapshot budget
  def expected_snapshot_budget
    recent = @extractor.snapshots.count { |s| recent_snapshot?(s) }
    [ recent, 10 ].max.round
  end

  # Whether a snapshot falls inside the reference window relative to the
  # evaluation clock.
  #
  # @param snapshot [Hash] a raw snapshot with a timestamp-ms field
  # @return [Boolean]
  def recent_snapshot?(snapshot)
    ms = snapshot["timestamp-ms"] || snapshot["timestamp_ms"]
    return false if ms.nil?

    Time.at(ms.to_f / 1000.0) >= @now - REFERENCE_SNAPSHOT_WINDOW_DAYS.days
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
