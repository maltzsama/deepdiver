require "rails_helper"

RSpec.describe ExecuteMaintenanceJob, type: :job do
  let(:plan) { create(:maintenance_plan, :with_all_steps) }

  before { TrinoRuntime.adapter = FakeTrinoRuntime.new }

  def released_execution
    e = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))
    e.update!(status: :running)
    e
  end

  it "executes the steps in canonical order" do
    execution = released_execution
    4.times { described_class.perform_now(execution.id) }

    expect(execution.execution_steps.order(:started_at).pluck(:operation))
      .to eq(MaintenancePlan::CANONICAL_ORDER)
  end

  it "skips a disabled step without breaking the chain" do
    plan.maintenance_steps.find_by(operation: "optimize_manifests").update!(enabled: false)
    execution = released_execution

    4.times { described_class.perform_now(execution.id) }

    expect(execution.execution_steps.find_by(operation: "optimize_manifests").status).to eq("skipped")
    expect(execution.execution_steps.find_by(operation: "remove_orphan_files").status).to eq("succeeded")
  end

  it "stops the chain when a step fails" do
    execution = released_execution
    allow(TrinoRuntime).to receive(:execute).and_raise("permission error")

    described_class.perform_now(execution.id)

    expect(execution.reload.status).to eq("failed")
    expect(execution.execution_steps.where(status: "succeeded")).to be_empty
    expect(execution.execution_steps.where(status: "failed").count).to eq(1)
  end

  it "records the duration of each step" do
    execution = released_execution
    described_class.perform_now(execution.id)

    step = execution.execution_steps.first
    expect(step.started_at).to be_present
    expect(step.finished_at).to be_present
  end

  it "does not advance the chain or tear down the engine on a commit conflict" do
    execution = released_execution
    allow(TrinoRuntime).to receive(:execute).and_raise(TrinoRuntime::CommitConflict)

    described_class.perform_now(execution.id)

    expect(execution.reload.status).to eq("running")
    expect(execution.execution_steps.first.retry_count).to eq(1)
  end

  it "drains when a failure drops the last demand" do
    execution = released_execution
    TrinoEngineSupervisor.state.update!(status: "up", status_changed_at: Time.current)
    allow(TrinoRuntime).to receive(:execute).and_raise("permission error")

    described_class.perform_now(execution.id)

    expect(execution.reload.status).to eq("failed")
    expect(TrinoEngineSupervisor.state.reload.status).to eq("draining")
  end

  it "releases the table lock when the chain finishes successfully" do
    execution = released_execution
    TableLock.acquire(execution)

    5.times { described_class.perform_now(execution.id) }

    expect(execution.reload.status).to eq("success")
    expect(TableLock.exists?(execution_history_id: execution.id)).to be(false)
  end
end
