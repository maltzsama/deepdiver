require "rails_helper"

RSpec.describe ExecuteMaintenanceJob, type: :job do
  def conflict_runtime
    Class.new(FakeTrinoRuntime) do
      def execute(sql, execution_id:, execution: nil)
        raise TrinoRuntime::CommitConflict, "concurrent commit"
      end
    end.new
  end

  it "keeps the execution as demand on a commit conflict and enqueues a backoff retry" do
    execution = create(:execution_history, status: :running, current_step: :executing_sql)
    TableLock.acquire(execution)
    TrinoRuntime.adapter = conflict_runtime

    described_class.perform_now(execution.id)

    execution.reload
    expect(execution.retry_count).to eq(1)
    expect(execution.status).to eq("running")

    enqueued = enqueued_jobs.map { |job| job[:job] }
    expect(enqueued).to include(ExecuteMaintenanceJob)

    # The engine is not torn down per execution; the per-table lock is freed.
    expect(enqueued).not_to include(DrainEngineJob)
    expect(TableLock.count).to eq(0)
  end
end
