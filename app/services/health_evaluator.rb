# Scores table health on a 0-100 scale from the synchronised metadata.
#   unknown  - no snapshot information yet
#   healthy  - score >= 70
#   warning  - 40 <= score < 70
#   critical - score < 40
#
# Penalties are accumulating, so large stale data always bottoms out at 0.
class HealthEvaluator
  STALE_24H = 40
  STALE_48H = 60
  STALE_7D = 80
  SNAPSHOT_FLOOR = 50
  SNAPSHOT_HIGH = 200
  SNAPSHOT_PENALTY = 10
  SNAPSHOT_HIGH_PENALTY = 20

  HEALTHY_BOUNDARY = 70
  WARNING_BOUNDARY = 40

  def self.evaluate(extractor, now: Time.current)
    new(extractor, now: now).call
  end

  def initialize(extractor, now:)
    @extractor = extractor
    @now = now
  end

  def call
    last_at = @extractor.last_snapshot_at
    return { score: nil, status: :unknown } unless last_at

    score = 100
    score -= staleness_penalty(last_at)
    score -= snapshot_count_penalty(@extractor.snapshot_count)

    { score: score.clamp(0, 100).to_i, status: status_for(score.clamp(0, 100).to_i) }
  end

  private

  def staleness_penalty(last_at)
    age = @now - last_at
    if age > 7.days
      STALE_7D
    elsif age > 48.hours
      STALE_48H
    elsif age > 24.hours
      STALE_24H
    else
      0
    end
  end

  def snapshot_count_penalty(count)
    return 0 if count <= SNAPSHOT_FLOOR

    count > SNAPSHOT_HIGH ? SNAPSHOT_HIGH_PENALTY : SNAPSHOT_PENALTY
  end

  def status_for(score)
    return :healthy if score >= HEALTHY_BOUNDARY
    return :warning if score >= WARNING_BOUNDARY

    :critical
  end
end
