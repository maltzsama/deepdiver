require "rails_helper"

RSpec.describe ApplicationHelper, "engine stepper progress model", type: :helper do
  describe "#median" do
    it "is nil with nothing to average" do
      expect(helper.median([])).to be_nil
    end

    it "averages the two middle values for an even count" do
      expect(helper.median([ 10, 20, 30, 40 ])).to eq(25.0)
    end

    it "takes the middle value for an odd count" do
      expect(helper.median([ 30, 10, 20 ])).to eq(20.0)
    end
  end

  describe "#engine_phase_estimates" do
    def session(ready:, drain:, outcome: :clean)
      ApplicationHelper::EngineSession.new(generation: 1, started_at: Time.current,
                                          ready_seconds: ready, drain_seconds: drain,
                                          uptime_seconds: 60, attempts: 1, outcome: outcome)
    end

    it "derives the median ready and drain times from completed sessions" do
      sessions = [ session(ready: 21.6, drain: 1.8), session(ready: 23.5, drain: 1.5),
                   session(ready: 40.1, drain: 1.2) ]

      estimates = helper.engine_phase_estimates(sessions)

      expect(estimates[:starting]).to eq(23.5)
      expect(estimates[:draining]).to eq(1.5)
    end

    it "ignores a running session, which has no final duration" do
      sessions = [ session(ready: 20, drain: 2), session(ready: 999, drain: 999, outcome: :running) ]

      expect(helper.engine_phase_estimates(sessions)[:starting]).to eq(20.0)
    end

    it "is nil per phase when no session has completed" do
      estimates = helper.engine_phase_estimates([ session(ready: nil, drain: nil, outcome: :running) ])

      expect(estimates[:starting]).to be_nil
      expect(estimates[:draining]).to be_nil
    end
  end

  describe "#engine_lifecycle_stepper" do
    it "gives each passed connector its own stage class, so the line accumulates" do
      html = helper.engine_lifecycle_stepper("draining")

      expect(html).to include("step-link--down done")
      expect(html).to include("step-link--starting done")
      expect(html).to include("step-link--up done")
    end

    it "marks the in-flight connector as progress" do
      expect(helper.engine_lifecycle_stepper("starting")).to include("progress")
    end

    it "renders idle as resting rather than as stuck at the first stage" do
      idle = helper.engine_lifecycle_stepper("down", idle: true)
      busy = helper.engine_lifecycle_stepper("down", idle: false)

      expect(idle).to include("resting")
      expect(idle).to include("step--down step active idle").or include("idle")
      expect(busy).not_to include("resting")
    end

    it "keeps the failed segment red instead of reverting the line to grey" do
      html = helper.engine_lifecycle_stepper("down", failed_at: "starting")

      expect(html).to include("step-link--starting failed")
    end
  end

  describe "#engine_failed_stage" do
    it "names the starting segment when the engine carries an error" do
      state = TrinoEngineState.instance(status: "down", status_changed_at: Time.current)
      state.update!(last_error: "engine start timed out")

      expect(helper.engine_failed_stage(state)).to eq("starting")
    end

    it "is nil for a clean state" do
      state = TrinoEngineState.instance(status: "up", status_changed_at: Time.current)
      state.update!(last_error: nil)

      expect(helper.engine_failed_stage(state)).to be_nil
    end
  end
end

RSpec.describe ApplicationHelper, "per-session coordinator identity", type: :helper do
  def lifecycle_event(state:, generation:, coordinator:, at:)
    ErrorEvent.create!(schema: "engine", operation: "engine-lifecycle", table: "",
                       source_system: "engine", severity: "info", status: "resolved",
                       message: "engine #{state} (generation #{generation})",
                       first_seen_at: at, last_seen_at: at,
                       context: { "state" => state, "generation" => generation,
                                  "attempts" => 1, "coordinator" => coordinator })
  end

  it "reports the coordinator recorded when the session started" do
    base = Time.current - 1.hour
    events = [
      lifecycle_event(state: "starting", generation: 10, coordinator: "ns/coord-aaa", at: base),
      lifecycle_event(state: "up",       generation: 11, coordinator: "ns/coord-aaa", at: base + 20.seconds),
      lifecycle_event(state: "down",     generation: 12, coordinator: "ns/coord-aaa", at: base + 80.seconds)
    ]

    session = helper.engine_sessions(events).first

    expect(session.coordinator).to eq("ns/coord-aaa")
  end

  it "keeps each session on its own coordinator rather than the newest one" do
    base = Time.current - 2.hours
    events = [
      lifecycle_event(state: "starting", generation: 1, coordinator: "ns/coord-old", at: base),
      lifecycle_event(state: "down",     generation: 2, coordinator: "ns/coord-old", at: base + 60.seconds),
      lifecycle_event(state: "starting", generation: 3, coordinator: "ns/coord-new", at: base + 30.minutes),
      lifecycle_event(state: "down",     generation: 4, coordinator: "ns/coord-new", at: base + 31.minutes)
    ]

    coordinators = helper.engine_sessions(events).map(&:coordinator)

    expect(coordinators).to contain_exactly("ns/coord-new", "ns/coord-old")
  end

  it "renders an em dash for a session recorded before the identity was captured" do
    base = Time.current - 1.hour
    events = [ lifecycle_event(state: "starting", generation: 1, coordinator: nil, at: base) ]

    expect(helper.engine_sessions(events).first.coordinator).to be_nil
  end
end
