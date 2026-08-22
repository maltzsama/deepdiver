require "rails_helper"

RSpec.describe ExecutionTimeline do
  let(:table) { create(:iceberg_table) }
  let(:execution) do
    create(:execution_history, iceberg_table: table, status: :running,
                               started_at: start_time)
  end
  let(:start_time) { Time.zone.parse("2026-08-21 17:49:31") }
  let(:now) { Time.zone.parse("2026-08-21 18:00:00") }
  let(:timeline) { described_class.new(execution, now: now) }

  def add_step(operation:, status:, started_at: nil, finished_at: nil, metrics: {})
    create(:execution_step, execution_history: execution, operation: operation,
                            status: status, started_at: started_at,
                            finished_at: finished_at, metrics: metrics)
  end

  it "produces no segments without a start time" do
    execution.update!(started_at: nil)

    expect(timeline.segments).to be_empty
    expect(timeline.total_seconds).to eq(0.0)
  end

  it "produces no segments for zero duration" do
    execution.update!(finished_at: start_time)

    expect(timeline.segments).to be_empty
    expect(timeline.total_seconds).to eq(0.0)
  end

  context "with a wait gap and two sequential steps" do
    before do
      # optimize starts 37s after the execution was created.
      add_step(operation: "optimize", status: :failed,
               started_at: start_time + 37.seconds,
               finished_at: start_time + 67.seconds)
      add_step(operation: "expire_snapshots", status: :succeeded,
               started_at: start_time + 69.seconds,
               finished_at: start_time + 75.seconds,
               metrics: { "stats" => { "processedBytes" => 1000, "physicalWrittenBytes" => 500 } })
      execution.update!(finished_at: start_time + 80.seconds)
    end

    it "opens with the wait segment covering queue hops, lock and boot" do
      wait = timeline.segments.first

      expect(wait.kind).to eq(:wait)
      expect(timeline.wait_seconds).to eq(37.0)
      expect(timeline.total_seconds).to eq(80.0)
      expect(wait.offset_pct).to eq(0.0)
      expect(wait.width_pct).to eq((37.0 / 80.0 * 100).round(2))
    end

    it "positions steps by absolute offset, preserving the 2s hole" do
      segs = timeline.segments
      optimize = segs.find { |s| s.label == "optimize" }
      expire   = segs.find { |s| s.label == "expire_snapshots" }

      expect(optimize.kind).to eq(:failed_step)
      expect(optimize.offset_pct).to eq((37.0 / 80.0 * 100).round(2))
      expect(expire.offset_pct).to eq((69.0 / 80.0 * 100).round(2))
      # The optimize segment ends before expire begins: 67s..69s stays empty track.
      expect(optimize.offset_pct + optimize.width_pct).to be < expire.offset_pct
    end

    it "sums bytes only from captured metrics" do
      expect(timeline.bytes_processed).to eq(1000)
      expect(timeline.bytes_written).to eq(500)
    end

    it "is closed when the execution has finished" do
      expect(timeline.running?).to be(false)
    end
  end

  context "with a running step" do
    before do
      add_step(operation: "optimize", status: :running, started_at: start_time + 5.seconds)
    end

    it "marks the last segment open and stretches it to now" do
      seg = timeline.segments.last

      expect(seg.kind).to eq(:open)
      expect(seg.duration).to eq(624.0)
      expect(timeline.running?).to be(true)
    end

    it "counts the wait before the first step" do
      expect(timeline.wait_seconds).to eq(5.0)
    end
  end

  context "when nothing ever started" do
    before do
      add_step(operation: "optimize", status: :pending)
      add_step(operation: "expire_snapshots", status: :blocked)
    end

    it "has nil wait and no step segments" do
      expect(timeline.wait_seconds).to be_nil
      expect(timeline.segments.select { |s| s.kind != :wait }).to be_empty
    end
  end

  context "when the execution failed before any step" do
    before do
      execution.update!(status: :failed, finished_at: start_time + 30.seconds)
    end

    it "leaves the bar empty; the view renders full-wait styling" do
      expect(timeline.segments).to be_empty
      expect(timeline.total_seconds).to eq(30.0)
    end
  end
end
