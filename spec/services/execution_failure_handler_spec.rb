require "rails_helper"

RSpec.describe ExecutionFailureHandler do
  let(:table) { create(:iceberg_table) }
  let(:plan)  { create(:maintenance_plan, iceberg_table: table) }
  let(:execution) do
    create(:execution_history, iceberg_table: table, maintenance_plan: plan,
                               status: :running, current_step: :expire_snapshots)
  end

  before do
    create(:execution_step, execution_history: execution, operation: "optimize", status: :succeeded)
    create(:execution_step, execution_history: execution, operation: "expire_snapshots", status: :failed,
                            error_message: "boom")
    create(:execution_step, execution_history: execution, operation: "optimize_manifests", status: :pending)
    create(:execution_step, execution_history: execution, operation: "remove_orphan_files", status: :pending)
  end

  it "blocks the steps that will never run when the chain aborts" do
    described_class.handle(execution, "expire_snapshots on reporting.t1 (c1): boom")

    execution.reload
    expect(execution.status).to eq("failed")
    expect(execution.finished_at).to be_present
    expect(execution.execution_steps.where(status: "pending")).to be_empty

    blocked = execution.execution_steps.where(status: "blocked").order(:id)
    expect(blocked.pluck(:operation)).to eq(%w[optimize_manifests remove_orphan_files])
    expect(blocked.pluck(:skip_reason)).to all(include("chain aborted"))
    expect(blocked.pluck(:skip_reason)).to all(include("expire_snapshots"))
    # error_message stays operational-only: blocked steps carry none.
    expect(blocked.pluck(:error_message)).to all(be_nil)
  end

  it "does not re-block or rewrite a terminal execution" do
    execution.update!(status: :failed)

    expect { described_class.handle(execution, "late duplicate") }
      .not_to change { execution.reload.error_message }
  end

  it "does not double-count a plan failure when an execution is handled twice" do
    described_class.handle(execution, "first failure")
    failures_before = plan.reload.consecutive_failures

    described_class.handle(execution.reload, "second handling")

    expect(plan.reload.consecutive_failures).to eq(failures_before)
  end

  it "leaves pending steps alone while the execution keeps running" do
    # No handler call: a running execution's pending steps are legitimate.
    expect(execution.execution_steps.where(status: "pending").count).to eq(2)
  end
end
