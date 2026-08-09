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

  WEIGHTS = {
    fragmentation:    40,
    snapshot_buildup: 30,
    delete_overhead: 20,
    manifest_buildup: 10
  }.freeze

  def self.evaluate(extractor, plan: nil, now: Time.current)
    new(extractor, plan: plan, now: now).call
  end

  def initialize(extractor, plan: nil, now: Time.current)
    @extractor = extractor
    @plan = plan
    @now = now
  end

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

  def snapshot_buildup
    count = @extractor.snapshot_count
    return nil if count.nil? || count.zero?

    budget = expected_snapshot_budget
    (1.0 - ((count - budget).to_f / budget)).clamp(0.0, 1.0)
  end

  def delete_overhead
    records = @extractor.total_records
    deletes = [ @extractor.position_deletes, @extractor.equality_deletes ].compact.sum
    return nil if records.nil? || records.zero? || (@extractor.position_deletes.nil? && @extractor.equality_deletes.nil?)

    (1.0 - (deletes.to_f / records) * 10).clamp(0.0, 1.0)
  end

  # No data source yet - see the note below.
  def manifest_buildup = nil

  def target_file_size
    @extractor.properties["write.target-file-size-bytes"]&.to_i.presence || DEFAULT_TARGET_FILE_SIZE
  end

  def expected_snapshot_budget
    return 50 if @plan.nil?

    days = @plan.maintenance_steps.find_by(operation: "expire_snapshots")
                &.config&.dig("retention_threshold").to_s[/\d+/]&.to_i || 7
    [ days * 10, 10 ].max
  end

  def status_for(score)
    return :healthy if score >= HEALTHY_BOUNDARY
    return :warning if score >= WARNING_BOUNDARY

    :critical
  end
end
