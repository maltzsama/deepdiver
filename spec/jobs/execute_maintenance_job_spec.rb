require "rails_helper"

RSpec.describe ExecuteMaintenanceJob, type: :job do
  def conflict_runtime
    Class.new(FakeTrinoRuntime) do
      def execute(sql, execution_id:)
        raise TrinoRuntime::CommitConflict, "concurrent commit"
      end
    end.new
  end

  it "keeps the lock and does not scale down while awaiting a retry" do
    execution = create(:execution_history, status: :running, current_step: :executing_sql)
    TrinoLock.acquire(execution.id)
    TrinoRuntime.adapter = conflict_runtime

    described_class.perform_now(execution.id)

    execution.reload
    expect(execution.awaiting_retry?).to be true
    expect(execution.retry_count).to eq(1)
    expect(TrinoLock.find_by(key: TrinoLock::GLOBAL_KEY).execution_history_id).to eq(execution.id)

    enqueued = enqueued_jobs.map { |job| job[:job] }
    expect(enqueued).to include(ExecuteMaintenanceJob)
    expect(enqueued).not_to include(ScaleDownJob)
  end
end
