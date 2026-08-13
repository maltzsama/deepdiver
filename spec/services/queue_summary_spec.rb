require "rails_helper"

RSpec.describe QueueSummary do
  # The Solid Queue tables only exist in production (separate `queue` database).
  # In dev/test the models raise on any query; the summary must degrade to zero
  # counts instead of crashing the activity screen.
  it "degrades to empty when the queue tables are absent" do
    result = described_class.new.call

    expect(result).to eq(ready: 0, scheduled: 0, running: 0, failed: 0, processes: 0, next_jobs: [])
  end
end
