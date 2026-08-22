require "rails_helper"

RSpec.describe SuperviseEngineStartJob, type: :job do
  it "brings the engine up and releases pending executions" do
    table = create(:iceberg_table)
    execution = create(:execution_history, iceberg_table: table, status: :pending, current_step: :start)
    TrinoEngineSupervisor.state.update!(status: "starting", status_changed_at: Time.current)

    described_class.perform_now

    expect(TrinoEngineSupervisor.state.status).to eq("up")
    expect(execution.reload.status).to eq("running")
    expect(enqueued_jobs.map { |j| j[:job] }).to include(ExecuteMaintenanceJob)
  end

  it "marks the engine failed and fails pending executions after max attempts" do
    table = create(:iceberg_table)
    pending = create(:execution_history, iceberg_table: table, status: :pending, current_step: :start)
    state = TrinoEngineSupervisor.state
    state.update!(status: "starting", start_attempts: TrinoEngineSupervisor::MAX_START_ATTEMPTS,
                  status_changed_at: Time.current)

    provisioner = Object.new
    def provisioner.exists? = false
    def provisioner.healthy? = false
    def provisioner.rollout_complete? = false
    def provisioner.idle? = true
    def provisioner.create! = raise(TrinoProvisioner::Error, "no cluster")
    def provisioner.destroy!; end
    def provisioner.wait_gone!(timeout:); end
    TrinoProvisioner.adapter = provisioner

    described_class.perform_now

    expect(TrinoEngineSupervisor.state.status).to eq("failed")
    expect(pending.reload.status).to eq("failed")
  end
end
