# Turns an ExecutionHistory into proportional timeline segments for the
# Operations list. One bar per execution: wait (queue hops + lock + engine
# boot, END-TO-END - it is NOT pure engine boot), then one segment per started
# step, gaps preserved as empty track. All math lives here; views only print.
#
# Scale is per-row: 100% of the bar equals that execution's own duration.
class ExecutionTimeline
  Segment = Data.define(:kind, :label, :duration, :offset_pct, :width_pct)

  # Creates the timeline for one execution.
  #
  # @param execution [ExecutionHistory] the execution to lay out
  # @param now [Time] the reference clock for open-ended segments
  def initialize(execution, now: Time.current)
    @execution = execution
    @now = now
  end

  # Timeline segments in chronological order: wait, then each started step.
  # Steps never started (skipped/blocked/pending) do NOT produce a segment -
  # the view marks them as a dashed tick plus a legend mention.
  #
  # @return [Array<Segment>] kind is one of :wait, :step, :failed_step, :open
  def segments
    return [] if start_time.nil? || total_seconds <= 0

    segs = []
    segs << Segment.new(:wait, nil, wait_seconds, 0, pct(wait_seconds)) if wait_seconds.to_f.positive?

    started_steps.each do |step|
      seg_end = step.finished_at || end_reference
      duration = (seg_end - step.started_at).to_f
      kind = step.status == "failed" ? :failed_step : (step.finished_at ? :step : :open)
      segs << Segment.new(kind, step.operation, duration,
                          pct(step.started_at - start_time), pct(duration))
    end
    segs
  end

  # Total wall-clock span the bar represents.
  #
  # @return [Float] seconds; 0.0 when there is nothing to draw
  def total_seconds
    return 0.0 if start_time.nil? || end_reference.nil?

    (end_reference - start_time).to_f.clamp(0.0, Float::INFINITY)
  end

  # End-to-end wait: creation until the first step actually began. Covers
  # queue latency, job hops, table lock and engine boot together.
  #
  # @return [Float, nil] seconds, nil when no step ever started
  def wait_seconds
    first = first_started_step
    return nil if first.nil?

    (first.started_at - start_time).to_f.clamp(0.0, Float::INFINITY)
  end

  # Sum of Trino processed bytes across the steps' captured metrics.
  #
  # @return [Integer]
  def bytes_processed
    stats_sum("processedBytes")
  end

  # Sum of Trino physically written bytes across the steps' captured metrics.
  #
  # @return [Integer]
  def bytes_written
    stats_sum("physicalWrittenBytes")
  end

  # Whether the execution is mid-flight (bar needs an open right edge).
  #
  # @return [Boolean]
  def running? = @execution.finished_at.nil? && @execution.started_at.present?

  private

  # Execution start (T0 of every offset).
  def start_time = @execution.started_at

  # Bar end: finish time, or the clock for in-flight executions.
  def end_reference
    return @execution.finished_at if @execution.finished_at.present?
    return @now if running?

    nil
  end

  # First step that ever started; id order equals plan position order because
  # run_plan materializes following maintenance_steps.position.
  def first_started_step
    started_steps.first
  end

  # Steps with a real start timestamp, chain order.
  def started_steps
    @execution.execution_steps.where.not(started_at: nil).order(:id)
  end

  # Fraction of the total span, clamped to a valid percentage.
  def pct(seconds)
    return 0.0 if total_seconds <= 0

    (seconds.to_f / total_seconds * 100).clamp(0.0, 100.0)
  end

  # Sums one metric field across all steps' Trino stats blobs.
  def stats_sum(field)
    @execution.execution_steps.filter_map { |s| s.metrics&.dig("stats", field) }.sum
  end
end
