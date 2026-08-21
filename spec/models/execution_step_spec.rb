require "rails_helper"

RSpec.describe ExecutionStep, type: :model do
  it "includes blocked in its statuses" do
    expect(ExecutionStep::STATUSES).to include("blocked")
    expect(ExecutionStep.blocked).to respond_to(:each)
  end
end
