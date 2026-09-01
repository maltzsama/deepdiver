require "rails_helper"

RSpec.describe ApplicationHelper, "#pager_nav", type: :helper do
  let(:pagy) { Pagy::Offset.new(count: 5000, page: 50, limit: 50) }

  it "renders styled pages with gap and active page badge" do
    html = helper.pager_nav(pagy)

    expect(html).to include("pager-gap")
    expect(html).to include('aria-current="page"')
    expect(html).to include("badge-ok")
    expect(html).not_to include("pager-disabled")
    # URLs preserve query params and the current page renders as active badge
    expect(html).to include("page=49")
    expect(html).to include(">50</span>")
  end

  it "dims the previous arrow on the first page" do
    html = helper.pager_nav(Pagy::Offset.new(count: 5000, page: 1, limit: 50))

    expect(html).to include("pager-disabled")
  end

  it "returns nil for a single page" do
    expect(helper.pager_nav(Pagy::Offset.new(count: 10, limit: 50))).to be_nil
  end
end

RSpec.describe ApplicationHelper, "#engine_lifecycle_stepper", type: :helper do
  it "emits stage nodes joined by connectors, with its own step-- modifiers" do
    html = helper.engine_lifecycle_stepper("starting")

    expect(html.scan(%r{class="step step--}).size).to eq(5)
    expect(html.scan("step-link").size).to eq(4)
    expect(html).to include("step-dot")
    expect(html).to include("step step--starting active")
    expect(html).not_to include("badge-")
    expect(html).not_to include("step-sep")
  end

  it "marks past stages done and future ones plain" do
    html = helper.engine_lifecycle_stepper("up")

    expect(html).to include("step step--down done")
    expect(html).not_to include("step step--down active")
    expect(html).to include("step step--up active")
  end

  it "wires the active→next connector as the progress bar for timed states" do
    html = helper.engine_lifecycle_stepper("draining", timer: true)

    expect(html).to include("step-link progress bar-warn")
    expect(html).to include('data-engine-timer-target="bar"')
  end

  it "does not wire the timer when timer: false" do
    html = helper.engine_lifecycle_stepper("draining")

    expect(html).to include("step-link progress bar-warn")
    expect(html).not_to include("data-engine-timer-target")
  end

  it "highlights stopping as the final active stage (no connector after it)" do
    html = helper.engine_lifecycle_stepper("stopping")

    expect(html).to include("step step--stopping active")
    # stopping is the last stage, so every connector before it is done and
    # there is no progress connector after the final node.
    expect(html.scan("step-link progress").size).to eq(0)
  end
end

RSpec.describe ApplicationHelper, "#engine_phase_time", type: :helper do
  it "shows the remaining time for a starting engine" do
    state = TrinoEngineState.new(status: "starting", status_changed_at: Time.current)
    allow(helper).to receive(:distance_of_time_in_words_to_now).and_return("5 min")

    expect(helper.engine_phase_time(state)).to include("5 min before timeout")
  end

  it "shows the uptime for an up engine" do
    state = TrinoEngineState.new(status: "up", status_changed_at: 10.minutes.ago)
    allow(helper).to receive(:time_ago_in_words).and_return("10 minutes")

    expect(helper.engine_phase_time(state)).to eq("Up for 10 minutes")
  end

  it "returns nil for a down engine" do
    expect(helper.engine_phase_time(TrinoEngineState.new(status: "down"))).to be_nil
  end
end

RSpec.describe ApplicationHelper, "#engine_sessions", type: :helper do
  def lifecycle_event(gen, state, at, attempts: 0)
    create(:error_event, context: { "generation" => gen, "state" => state, "attempts" => attempts },
                         last_seen_at: at)
  end

  it "collapses a generation's transitions into a single session" do
    t = Time.zone.parse("2026-09-01 10:00:00")
    events = [
      lifecycle_event(1, "starting", t),
      lifecycle_event(1, "up", t + 34.seconds),
      lifecycle_event(1, "draining", t + 15.minutes),
      lifecycle_event(1, "down", t + 15.minutes + 3.seconds)
    ]

    sessions = helper.engine_sessions(events)

    expect(sessions.size).to eq(1)
    session = sessions.first
    expect(session.generation).to eq(1)
    expect(session.started_at).to eq(t)
    expect(session.ready_seconds).to eq(34)
    expect(session.uptime_seconds).to eq(866)
    expect(session.drain_seconds).to eq(3)
    expect(session.outcome).to eq(:clean)
    expect(session).not_to be_running
  end

  it "labels a still-running session and sorts it to the top" do
    t = Time.zone.parse("2026-09-01 10:00:00")
    events = [
      lifecycle_event(2, "starting", t - 1.hour),
      lifecycle_event(2, "up", t - 1.hour + 30.seconds),
      lifecycle_event(1, "starting", t - 3.hours),
      lifecycle_event(1, "up", t - 3.hours + 40.seconds),
      lifecycle_event(1, "draining", t - 2.hours),
      lifecycle_event(1, "down", t - 2.hours + 5.seconds)
    ]

    sessions = helper.engine_sessions(events)

    expect(sessions.size).to eq(2)
    expect(sessions.first.generation).to eq(2)
    expect(sessions.first.outcome).to eq(:running)
    expect(sessions.first).to be_running
    expect(sessions.first.uptime_seconds).to be_within(5).of(Time.current - (t - 1.hour + 30.seconds))
  end

  it "labels a failed start when a generation never reached up" do
    t = Time.zone.parse("2026-09-01 10:00:00")
    events = [
      lifecycle_event(3, "starting", t, attempts: 3),
      lifecycle_event(3, "down", t + 1.minute, attempts: 3)
    ]

    session = helper.engine_sessions(events).first

    expect(session.outcome).to eq(:failed)
    expect(session.attempts).to eq(3)
    expect(session.uptime_seconds).to be_nil
  end

  it "keeps nil durations for phases that fell outside the event window" do
    t = Time.zone.parse("2026-09-01 10:00:00")
    events = [
      lifecycle_event(4, "up", t),
      lifecycle_event(4, "down", t + 30.minutes)
    ]

    session = helper.engine_sessions(events).first

    expect(session.started_at).to eq(t)
    expect(session.ready_seconds).to be_nil
    expect(session.drain_seconds).to be_nil
    expect(session.outcome).to eq(:clean)
  end

  it "groups transitions with different generations into one session" do
    t = Time.zone.parse("2026-09-01 10:00:00")
    # Realistic: transition! bumps generation on EVERY transition (the CAS
    # guard's predicate), so a single engine run spans several generations.
    events = [
      lifecycle_event(10, "starting", t),
      lifecycle_event(11, "up", t + 34.seconds),
      lifecycle_event(12, "draining", t + 15.minutes),
      lifecycle_event(13, "down", t + 15.minutes + 3.seconds)
    ]

    sessions = helper.engine_sessions(events)

    expect(sessions.size).to eq(1)
    session = sessions.first
    expect(session.generation).to eq(10)
    expect(session.ready_seconds).to eq(34)
    expect(session.uptime_seconds).to eq(866)
    expect(session.drain_seconds).to eq(3)
    expect(session.outcome).to eq(:clean)
  end

  it "keeps two consecutive engine runs as two sessions" do
    t = Time.zone.parse("2026-09-01 10:00:00")
    events = [
      lifecycle_event(1, "starting", t - 2.hours),
      lifecycle_event(2, "up", t - 2.hours + 20.seconds),
      lifecycle_event(3, "down", t - 2.hours + 5.minutes),
      lifecycle_event(4, "starting", t),
      lifecycle_event(5, "up", t + 15.seconds)
    ]

    sessions = helper.engine_sessions(events)

    expect(sessions.size).to eq(2)
    expect(sessions.map(&:generation)).to contain_exactly(1, 4)
    expect(sessions.first.outcome).to eq(:running)
    expect(sessions.last.outcome).to eq(:clean)
  end
end

RSpec.describe ApplicationHelper, "#metadata_diff", type: :helper do
  let(:table) { create(:iceberg_table) }
  let(:execution) { create(:execution_history, iceberg_table: table) }

  it "renders a before/after row when a table metric moved" do
    execution.update!(
      metadata_before: { "total_data_files" => 10, "snapshot_count" => 5 },
      metadata_after:  { "total_data_files" => 8, "snapshot_count" => 5 }
    )
    create(:execution_step, execution_history: execution, operation: "optimize")

    html = helper.metadata_diff(execution)

    expect(html).to include("Data files")
    expect(html).to include("10")
    expect(html).to include("8")
  end

  it "shows manifest_count for optimize_manifests" do
    execution.update!(
      metadata_before: { "manifest_count" => 20 },
      metadata_after:  { "manifest_count" => 1 }
    )
    create(:execution_step, execution_history: execution, operation: "optimize_manifests")

    html = helper.metadata_diff(execution)

    expect(html).to include("Manifests")
    expect(html).to include("20")
    expect(html).to include("1")
  end

  it "falls back to step metrics when no table metric moved" do
    execution.update!(
      metadata_before: { "total_data_files" => 10, "snapshot_count" => 5 },
      metadata_after:  { "total_data_files" => 10, "snapshot_count" => 5 }
    )
    create(:execution_step, execution_history: execution, operation: "remove_orphan_files",
                            metrics: { "rows" => 5 })

    html = helper.metadata_diff(execution)

    expect(html).to include("5 processed")
  end

  it "returns nil when there is nothing to show" do
    execution.update!(
      metadata_before: { "total_data_files" => 10 },
      metadata_after:  { "total_data_files" => 10 }
    )
    create(:execution_step, execution_history: execution, operation: "remove_orphan_files",
                            metrics: { "rows" => 0 })

    expect(helper.metadata_diff(execution)).to be_nil
  end
end
