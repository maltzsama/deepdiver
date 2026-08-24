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

  it "returns the existing running execution instead of creating a duplicate" do
    previous = create(:execution_history, iceberg_table: table, status: :running)
    TableLock.acquire(previous)

    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))

    expect(execution.id).to eq(previous.id)
  end

  it "stamps last_heartbeat_at when transitioning to running" do
    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))
    expect(execution.last_heartbeat_at).to be_nil

    MaintenanceOrchestrator.start_execution_on_engine(execution.id)

    expect(execution.reload.status).to eq("running")
    expect(execution.last_heartbeat_at).to be_present
  end

  it "defers the maintenance enqueue until the primary transaction commits" do
    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))
    maintenance_jobs = -> { enqueued_jobs.count { |job| job[:job] == ExecuteMaintenanceJob } }

    # The supervisor dispatches inside a with_lock; the queue worker could
    # consume the job before the status: :running write is committed and skip
    # it as still pending. The enqueue must wait for the commit.
    ActiveRecord::Base.transaction do
      MaintenanceOrchestrator.start_execution_on_engine(execution.id)
      expect(maintenance_jobs.call).to eq(0)
    end

    expect(execution.reload.status).to eq("running")
    expect(maintenance_jobs.call).to eq(1)
  end

  it "skips for overlap when the lock is held by a different execution" do
    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))

    # Acquire the lock from outside — simulates another execution grabbing it
    # between run_plan and start_execution_on_engine.
    holder = create(:execution_history, iceberg_table: table, status: :running)
    TableLock.acquire(holder)

    MaintenanceOrchestrator.start_execution_on_engine(execution.id)

    expect(execution.reload.status).to eq("skipped")
    expect(execution.skip_reason).to include("still running")
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

  it "materializes skipped steps with skip_reason, never error_message" do
    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 02:00"))

    skipped = execution.execution_steps.where(status: "skipped")
    expect(skipped.where(error_message: nil).count).to eq(skipped.count)
    expect(skipped.where.not(skip_reason: nil).pluck(:skip_reason))
      .to all(match(/step disabled|outside cadence/))
  end

  it "keeps the default association order equal to the plan position order" do
    execution = MaintenanceOrchestrator.run_plan(plan.id, at: Time.zone.parse("2026-08-10 03:00"))

    expect(execution.execution_steps.pluck(:operation)).to eq(MaintenancePlan::CANONICAL_ORDER)
  end

  it "keeps chain order even when maintenance_steps rows were inserted out of position order" do
    other_table = create(:iceberg_table)
    shuffled = create(:maintenance_plan, iceberg_table: other_table, cron: "0 * * * *")
    # Insert deliberately against position order - the timeline bar depends on
    # id ASC matching plan position ASC.
    %w[remove_orphan_files optimize expire_snapshots optimize_manifests].zip([ 3, 0, 1, 2 ]) do |op, pos|
      create(:maintenance_step, maintenance_plan: shuffled, operation: op, position: pos, cadence_cron: nil)
    end

    execution = MaintenanceOrchestrator.run_plan(shuffled.id, at: Time.zone.parse("2026-08-10 03:00"))

    expect(execution.execution_steps.pluck(:operation)).to eq(MaintenancePlan::CANONICAL_ORDER)
  end
end
