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
