require "rails_helper"

RSpec.describe TrinoEngineSupervisor do
  let(:schedule) { create(:maintenance_schedule) }

  def enqueue_execution
    schedule.execution_histories.create!(status: :pending, current_step: :start)
  end

  it "starts the engine when an execution arrives while it is down" do
    execution = enqueue_execution

    described_class.on_execution_enqueued(execution)

    expect(described_class.state.status).to eq("starting")
    expect(enqueued_jobs.map { |j| j[:job] }).to include(SuperviseEngineStartJob)
  end

  it "releases an execution immediately when the engine is already up" do
    execution = enqueue_execution
    described_class.state.update!(status: "up", status_changed_at: Time.current)

    described_class.on_execution_enqueued(execution)

    expect(execution.reload.status).to eq("running")
    expect(enqueued_jobs.map { |j| j[:job] }).to include(ExecuteMaintenanceJob)
  end

  it "starts draining when the last execution finishes" do
    execution = schedule.execution_histories.create!(status: :success, current_step: :done)
    described_class.state.update!(status: "up", status_changed_at: Time.current)

    described_class.on_execution_finished(execution)

    expect(described_class.state.status).to eq("draining")
    expect(enqueued_jobs.map { |j| j[:job] }).to include(DrainEngineJob)
  end

  it "does not drain while demand remains" do
    running = schedule.execution_histories.create!(status: :running, current_step: :executing_sql)
    finished = schedule.execution_histories.create!(status: :success, current_step: :done)
    described_class.state.update!(status: "up", status_changed_at: Time.current)

    described_class.on_execution_finished(finished)

    expect(running.reload.status).to eq("running")
    expect(described_class.state.status).to eq("up")
  end
end
