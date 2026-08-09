require "rails_helper"

RSpec.describe "shared/_step_chain", type: :view do
  let(:schedule) { create(:maintenance_schedule) }

  def render_for(execution)
    render partial: "shared/step_chain", locals: { execution: execution }
    rendered
  end

  it "marks the current node as failed when the execution failed" do
    execution = schedule.execution_histories.create!(
      status: :failed, current_step: :executing_sql, error_message: "boom"
    )

    expect(render_for(execution)).to include("chain-here-fail")
  end

  it "marks the current node as retry and shows the counter when awaiting a new attempt" do
    execution = schedule.execution_histories.create!(
      status: :running, current_step: :executing_sql,
      awaiting_retry: true, retry_count: 2
    )

    output = render_for(execution)

    expect(output).to include("chain-here-retry")
    expect(output).to include("retry 2/#{ExecuteMaintenanceJob::MAX_RETRIES}")
    expect(output).not_to include("chain-here-fail")
  end

  it "does not confuse a normally running execution with a retry" do
    execution = schedule.execution_histories.create!(
      status: :running, current_step: :executing_sql, awaiting_retry: false
    )

    output = render_for(execution)

    expect(output).to include("chain-here-ok")
    expect(output).not_to include("chain-retry-badge")
  end
end