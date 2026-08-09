require "rails_helper"

RSpec.describe ExecuteMaintenanceJob, type: :job do
  let(:plan) { create(:maintenance_plan, :with_all_steps) }
  let(:execution) { create(:execution_history, maintenance_plan: plan, iceberg_table: plan.iceberg_table) }

  before { TrinoRuntime.adapter = FakeTrinoRuntime.new }

  it "executes the steps in canonical order" do
    4.times { described_class.perform_now(execution.id) }

    expect(execution.execution_steps.order(:started_at).pluck(:operation))
      .to eq(MaintenancePlan::CANONICAL_ORDER)
  end

  it "skips a disabled step without breaking the chain" do
    plan.maintenance_steps.find_by(operation: "optimize_manifests").update!(enabled: false)

    4.times { described_class.perform_now(execution.id) }

    expect(execution.execution_steps.find_by(operation: "optimize_manifests").status).to eq("skipped")
    expect(execution.execution_steps.find_by(operation: "remove_orphan_files").status).to eq("succeeded")
  end

  it "stops the chain when a step fails" do
    allow(TrinoRuntime).to receive(:execute).and_raise("permission error")

    described_class.perform_now(execution.id)

    expect(execution.reload.status).to eq("failed")
    expect(execution.execution_steps.where(status: "succeeded")).to be_empty
    expect(execution.execution_steps.count).to eq(1)
  end

  it "records the duration of each step" do
    described_class.perform_now(execution.id)

    step = execution.execution_steps.first
    expect(step.started_at).to be_present
    expect(step.finished_at).to be_present
  end

  it "does not advance the chain or tear down the engine on a commit conflict" do
    allow(TrinoRuntime).to receive(:execute).and_raise(TrinoRuntime::CommitConflict)

    described_class.perform_now(execution.id)

    expect(execution.reload.status).to eq("running")
    expect(execution.execution_steps.first.retry_count).to eq(1)
  end
end
