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

  it "re-enqueues shortly when the execution is still pending (primary commit not yet visible)" do
    execution = create(:execution_history, iceberg_table: plan.iceberg_table, status: :pending)

    described_class.perform_now(execution.id)

    expect(execution.reload.retry_count).to eq(1)
    retried = enqueued_jobs.last
    expect(retried[:job]).to eq(ExecuteMaintenanceJob)
    expect(retried[:at]).to be_between((Time.current + 1.second).to_f, (Time.current + 10.seconds).to_f)
  end

  it "fails a pending execution past the retry limit instead of abandoning it" do
    execution = create(:execution_history, iceberg_table: plan.iceberg_table, status: :pending,
                                           retry_count: described_class::MAX_RETRIES)

    described_class.perform_now(execution.id)

    # Abandoning it left "pending" demand forever: the engine never drained and
    # run_plan's already-queued guard blocked the table permanently.
    expect(execution.reload.status).to eq("failed")
    expect(execution.error_message).to match(/never became visible/)
    expect(TrinoDemand.maintenance_count).to eq(0)
  end

  it "does not re-enqueue once the retry limit is spent" do
    execution = create(:execution_history, iceberg_table: plan.iceberg_table, status: :pending,
                                           retry_count: described_class::MAX_RETRIES)

    expect { described_class.perform_now(execution.id) }
      .not_to change { enqueued_jobs.size }
  end

  it "clears the dispatch retry budget once the execution is visible as running" do
    execution = released_execution
    execution.update!(retry_count: 2)

    described_class.perform_now(execution.id)

    # Otherwise a healthy execution renders as "retrying" for the rest of the
    # chain (execution_visual_state reads retrying?).
    expect(execution.reload.retry_count).to eq(0)
    expect(execution).not_to be_retrying
  end

  it "skips (without retrying) an execution that is no longer running or pending" do
    execution = create(:execution_history, iceberg_table: plan.iceberg_table, status: :success)

    expect { described_class.perform_now(execution.id) }
      .not_to change { enqueued_jobs.size }

    expect(execution.reload.retry_count).to eq(0)
  end

  it "drains when a failure drops the last demand" do
    execution = released_execution
    TrinoEngineSupervisor.state.update!(status: "up", status_changed_at: Time.current)
    allow(TrinoRuntime).to receive(:execute).and_raise("permission error")

    described_class.perform_now(execution.id)

    expect(execution.reload.status).to eq("failed")
    expect(TrinoEngineSupervisor.state.reload.status).to eq("draining")
  end

  it "finishes a chain with no maintenance_plan without raising" do
    # maintenance_plan is optional: true on ExecutionHistory. finish_chain
    # called plan.update! unconditionally, which raised NoMethodError on nil.
    execution = create(:execution_history, iceberg_table: plan.iceberg_table,
                                           maintenance_plan: nil, status: :running)

    expect { described_class.perform_now(execution.id) }.not_to raise_error
    expect(execution.reload.status).to eq("success")
  end

  it "releases the table lock when the chain finishes successfully" do
    execution = released_execution
    TableLock.acquire(execution)

    5.times { described_class.perform_now(execution.id) }

    expect(execution.reload.status).to eq("success")
    expect(TableLock.exists?(execution_history_id: execution.id)).to be(false)
  end

  describe "before/after metadata snapshots" do
    it "captures metadata_before at chain start" do
      execution = released_execution

      described_class.perform_now(execution.id)

      expect(execution.reload.metadata_before).not_to be_nil
      expect(execution.metadata_before).to include("total_records", "snapshot_count")
    end

    it "captures metadata_after at chain end" do
      execution = released_execution
      5.times { described_class.perform_now(execution.id) }

      expect(execution.reload.metadata_after).not_to be_nil
      expect(execution.metadata_after).to include("total_records", "snapshot_count")
    end

    it "does not overwrite metadata_before on subsequent steps" do
      execution = released_execution
      described_class.perform_now(execution.id)
      before_snapshot = execution.reload.metadata_before

      described_class.perform_now(execution.id)

      expect(execution.reload.metadata_before).to eq(before_snapshot)
    end

    it "raises ErrorEvent when total_records decreases" do
      execution = released_execution
      described_class.perform_now(execution.id)

      execution.update!(status: :running, metadata_before: { "total_records" => 200 },
                                        metadata_after: { "total_records" => 100 })

      job = described_class.new
      expect { job.send(:check_records_integrity!, execution) }
        .to change { ErrorEvent.count }.by(1)

      event = ErrorEvent.last
      expect(event.operation).to eq("records-integrity")
      expect(event.severity).to eq("error")
      expect(event.message).to include("200").and include("100").and include("decreased")
    end

    it "ignores an increase in total_records (concurrent append)" do
      execution = released_execution
      described_class.perform_now(execution.id)

      execution.update!(status: :running, metadata_before: { "total_records" => 100 },
                                        metadata_after: { "total_records" => 200 })

      job = described_class.new
      expect { job.send(:check_records_integrity!, execution) }
        .not_to change { ErrorEvent.count }
    end

    it "skips integrity check when before total_records is nil" do
      execution = released_execution
      described_class.perform_now(execution.id)
      execution.update!(metadata_before: { "total_records" => nil },
                        metadata_after: { "total_records" => 200 })

      job = described_class.new
      expect { job.send(:check_records_integrity!, execution) }
        .not_to change { ErrorEvent.count }
    end

    it "skips integrity check when after total_records is nil" do
      execution = released_execution
      described_class.perform_now(execution.id)
      execution.update!(metadata_before: { "total_records" => 100 },
                        metadata_after: { "total_records" => nil })

      job = described_class.new
      expect { job.send(:check_records_integrity!, execution) }
        .not_to change { ErrorEvent.count }
    end
  end

  describe "partition-batched OPTIMIZE" do
    let(:table) { plan.iceberg_table }

    it "runs one statement per partition group and marks the step succeeded" do
      table.update!(partition_json: [ { "spec-id" => 0, "fields" => [ { "name" => "ingestion_date", "transform" => "identity" } ] } ])
      optimize = plan.maintenance_steps.find_by!(operation: "optimize")
      optimize.update!(config: { "partitions_per_query" => 2 })
      values = (1..5).map { |d| [ format("2026-01-%02d", d) ] }
      allow(TrinoRuntime).to receive(:query_rows).and_return(values)
      executed = []
      allow(TrinoRuntime).to receive(:execute) do |sql, **_kw|
        executed << sql
        { "query_id" => "q#{executed.size}", "rows" => 0 }
      end
      execution = released_execution

      described_class.perform_now(execution.id)

      step = execution.execution_steps.find_by!(operation: "optimize")
      expect(step.status).to eq("succeeded")
      expect(step.metrics["batched_statements"]).to eq(3)
      expect(executed.size).to eq(3)
      expect(executed.all? { |sql| sql.include?("WHERE \"ingestion_date\" IN") }).to be true
    end

    it "falls back to a single OPTIMIZE when the table is not batchable" do
      table.update!(partition_json: [])
      allow(TrinoRuntime).to receive(:query_rows)
      executed = []
      allow(TrinoRuntime).to receive(:execute) do |sql, **_kw|
        executed << sql
        { "query_id" => "q", "rows" => 0 }
      end
      execution = released_execution

      described_class.perform_now(execution.id)

      step = execution.execution_steps.find_by!(operation: "optimize")
      expect(step.status).to eq("succeeded")
      expect(step.metrics["batched_statements"]).to be_nil
      expect(executed.size).to eq(1)
      expect(executed.first).not_to include("WHERE")
    end
  end

  describe "post-success bookkeeping" do
    it "keeps a step succeeded when the broadcast raises" do
      allow(TrinoRuntime).to receive(:execute).and_return({ "query_id" => "q", "rows" => 0 })
      fail_broadcast = false
      allow(ActivityBroadcaster).to receive(:broadcast!).and_wrap_original do |original|
        original.call
        raise StandardError, "broadcast boom" if fail_broadcast
      end
      execution = released_execution
      fail_broadcast = true

      described_class.perform_now(execution.id)

      step = execution.execution_steps.find_by!(operation: "optimize")
      expect(step.status).to eq("succeeded")
      expect(execution.reload.status).to eq("running")
    end

    it "keeps a step succeeded when the next-chain enqueue raises" do
      allow(TrinoRuntime).to receive(:execute).and_return({ "query_id" => "q", "rows" => 0 })
      allow(MaintenanceOrchestrator).to receive(:execute_maintenance).and_raise(StandardError, "enqueue boom")
      execution = released_execution

      described_class.perform_now(execution.id)

      step = execution.execution_steps.find_by!(operation: "optimize")
      expect(step.status).to eq("succeeded")
      expect(execution.reload.status).to eq("running")
    end
  end
end
