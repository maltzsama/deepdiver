require "rails_helper"

RSpec.describe "Cadence per step" do
  let(:table) { create(:iceberg_table) }
  let(:plan)  { create(:maintenance_plan, iceberg_table: table, cron: "0 * * * *") }

  before do
    create(:maintenance_step, maintenance_plan: plan, operation: "optimize",
                              position: 0, cadence_cron: nil)
    create(:maintenance_step, maintenance_plan: plan, operation: "expire_snapshots",
                              position: 1, cadence_cron: "0 3 * * *")
    create(:maintenance_step, maintenance_plan: plan, operation: "optimize_manifests",
                              position: 2, cadence_cron: "0 3 * * *")
    create(:maintenance_step, maintenance_plan: plan, operation: "remove_orphan_files",
                              position: 3, cadence_cron: "0 3 * * *")
  end

  it "at 02:00 only compaction is due" do
    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 02:00"))

    expect(execution.execution_steps.where(status: "pending").pluck(:operation)).to eq([ "optimize" ])
    expect(execution.execution_steps.where(status: "skipped").count).to eq(3)
  end

  it "at 03:00 everything runs, in canonical order" do
    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))

    pending = execution.execution_steps.where(status: "pending")
                       .joins(:maintenance_step).order("maintenance_steps.position")
    expect(pending.pluck(:operation)).to eq(MaintenancePlan::CANONICAL_ORDER)
  end

  it "the order NEVER changes, even with different cadences" do
    %w[01:00 02:00 03:00 04:00].each do |hour|
      execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 #{hour}"))
      ordered = execution.execution_steps.joins(:maintenance_step)
                         .order("maintenance_steps.position").pluck(:operation)

      expect(ordered).to eq(MaintenancePlan::CANONICAL_ORDER)
    end
  end

  it "does not bring the engine up when nothing is due" do
    plan.maintenance_steps.find_by(operation: "optimize").update!(cadence_cron: "0 3 * * *")

    expect { MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 02:00")) }
      .not_to change { enqueued_jobs.size }

    execution = plan.execution_histories.last
    expect(execution.status).to eq("success")
    expect(execution.execution_steps.where(status: "pending")).to be_empty
  end

  it "records a dispatch skipped for overlap instead of losing it" do
    previous = create(:execution_history, iceberg_table: table, status: :running)
    TableLock.acquire(previous)

    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))
    MaintenanceOrchestrator.start_execution_on_engine(execution.id)

    expect(execution.reload.status).to eq("skipped")
    expect(execution.error_message).to include("still running")
  end

  it "reaps a stale lock left by a finished execution before running" do
    stale = create(:execution_history, iceberg_table: table, status: :success)
    TableLock.acquire(stale)

    expect { MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00")) }
      .to change { TableLock.count }.from(1).to(0)
  end

  it "does not enqueue a duplicate while a run is pending" do
    existing = create(:execution_history, iceberg_table: table, maintenance_plan: plan, status: :pending)

    expect { MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00")) }
      .not_to change { ExecutionHistory.count }
    expect(MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))).to eq(existing)
  end

  it "drains the engine when a dispatch is skipped and nothing else needs it" do
    TrinoEngineSupervisor.state.update!(status: "up", status_changed_at: Time.current)
    holder = create(:execution_history, iceberg_table: table, status: :success)
    TableLock.acquire(holder)
    execution = create(:execution_history, iceberg_table: table, status: :pending)

    MaintenanceOrchestrator.start_execution_on_engine(execution.id)

    expect(execution.reload.status).to eq("skipped")
    expect(TrinoEngineSupervisor.state.reload.status).to eq("draining")
  end
end
