require "rails_helper"

RSpec.describe TrinoEngineSupervisor do
  let(:table) { create(:iceberg_table) }

  def enqueue_execution
    create(:execution_history, iceberg_table: table, status: :pending, current_step: :start)
  end

  it "starts the engine when an execution arrives while it is down" do
    execution = enqueue_execution

    described_class.demand_arrived!

    expect(described_class.state.status).to eq("starting")
    expect(enqueued_jobs.map { |j| j[:job] }).to include(SuperviseEngineStartJob)
  end

  it "records each lifecycle transition as an engine error event" do
    execution = enqueue_execution

    expect { described_class.demand_arrived! }
      .to change { ErrorEvent.where(source_system: "engine", operation: "engine-lifecycle").count }.by(1)

    expect(ErrorEvent.where(source_system: "engine", operation: "engine-lifecycle").last.message)
      .to match(/engine starting \(generation \d+\)/)
  end

  it "releases an execution immediately when the engine is already up" do
    execution = enqueue_execution
    described_class.state.update!(status: "up", status_changed_at: Time.current)

    described_class.demand_arrived!(dispatch: -> { MaintenanceOrchestrator.start_execution_on_engine(execution.id) })

    expect(execution.reload.status).to eq("running")
    expect(enqueued_jobs.map { |j| j[:job] }).to include(ExecuteMaintenanceJob)
  end

  it "starts draining when the last execution finishes" do
    create(:execution_history, iceberg_table: table, status: :success, current_step: :done)
    described_class.state.update!(status: "up", status_changed_at: Time.current)

    described_class.demand_finished!

    expect(described_class.state.status).to eq("draining")
    expect(enqueued_jobs.map { |j| j[:job] }).to include(DrainEngineJob)
  end

  it "does not drain while demand remains" do
    create(:execution_history, iceberg_table: table, status: :running, current_step: :executing_sql)
    create(:execution_history, iceberg_table: table, status: :success, current_step: :done)
    described_class.state.update!(status: "up", status_changed_at: Time.current)

    described_class.demand_finished!

    expect(described_class.state.status).to eq("up")
  end

  describe "two demand sources" do
    it "counts maintenance and freshness together" do
      create(:execution_history, status: :running)
      create(:freshness_run, status: "running")

      expect(TrinoDemand.count).to eq(2)
      expect(TrinoDemand.breakdown).to eq(maintenance: 1, freshness: 1)
    end

    it "does not drain while the other source still has work" do
      create(:execution_history, status: :running)
      described_class.state.update!(status: "up")

      described_class.demand_finished!

      expect(described_class.state.reload.status).to eq("up")
    end
  end

  describe "destruction during acceptance" do
    it "does NOT destroy when demand arrives between the check and the destruction" do
      described_class.state.update!(status: "draining", drain_started_at: Time.current)

      create(:freshness_run, status: "pending")

      expect(described_class.begin_stopping!).to be(false)
      expect(described_class.state.reload.status).to eq("up")
    end

    it "does not dispatch new work once it has entered stopping" do
      described_class.state.update!(status: "draining", drain_started_at: Time.current)
      expect(described_class.begin_stopping!).to be(true)

      dispatched = false
      described_class.demand_arrived!(dispatch: -> { dispatched = true })

      expect(dispatched).to be(false)
      expect(described_class.state.reload.status).to eq("stopping")
    end

    it "starts again if demand arrived during stopping" do
      described_class.state.update!(status: "stopping", status_changed_at: Time.current)
      create(:freshness_run, status: "pending")

      expect(MaintenanceOrchestrator).to receive(:supervise_engine_start)
      described_class.finish_stopping!

      expect(described_class.state.reload.status).to eq("starting")
    end
  end

  describe "freshness without an enabled table" do
    it "does not create a run nor bring the engine up" do
      expect(MaintenanceOrchestrator.enqueue_freshness_sweep).to be_nil
      expect(described_class.state.reload.status).to eq("down")
    end
  end

  describe "concurrency" do
    before do
      skip "requires PostgreSQL row locking" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    end

    it "two sources arriving together produce ONE start" do
      described_class.state.update!(status: "down")
      expect(MaintenanceOrchestrator).to receive(:supervise_engine_start).once

      threads = 2.times.map do
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.demand_arrived! } }
      end
      threads.each(&:join)

      expect(described_class.state.reload.status).to eq("starting")
    end

    it "two simultaneous finishes produce ONE drain" do
      described_class.state.update!(status: "up")
      expect(MaintenanceOrchestrator).to receive(:drain_engine).once

      2.times.map do
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.demand_finished! } }
      end.each(&:join)

      expect(described_class.state.reload.status).to eq("draining")
    end
  end

  describe "hard reset step bookkeeping" do
    let(:table) { create(:iceberg_table) }
    let(:execution) { create(:execution_history, iceberg_table: table, status: :running) }

    it "blocks pending steps when the hard reset fails executions in flight" do
      create(:execution_step, execution_history: execution, operation: "optimize", status: :succeeded)
      create(:execution_step, execution_history: execution, operation: "expire_snapshots", status: :pending)

      described_class.hard_reset!

      execution.reload
      expect(execution.status).to eq("failed")
      blocked = execution.execution_steps.find_by(operation: "expire_snapshots")
      expect(blocked.status).to eq("blocked")
      expect(blocked.skip_reason).to eq("engine hard reset")
      expect(blocked.error_message).to be_nil
    end

    it "blocks pending steps of queued executions too" do
      queued = create(:execution_history, iceberg_table: table, status: :pending)
      create(:execution_step, execution_history: queued, operation: "optimize", status: :pending)

      described_class.hard_reset!

      expect(queued.execution_steps.where(status: "blocked").count).to eq(1)
    end
  end

  describe "transition! compare-and-set" do
    it "refuses to transition from a stale record" do
      state = described_class.state
      stale = TrinoEngineState.find(state.id)

      described_class.transition!(state, "starting")

      # `stale` still carries the old generation, so its UPDATE must match no
      # rows. Without the generation predicate this silently overwrote the
      # transition that just happened.
      expect { described_class.transition!(stale, "down") }
        .to raise_error(described_class::ConcurrentTransitionError, /CAS lost/)
      expect(state.reload.status).to eq("starting")
    end

    it "advances the generation on every accepted transition" do
      state = described_class.state
      before = state.generation

      described_class.transition!(state, "starting")

      expect(state.reload.generation).to eq(before + 1)
    end
  end
end
