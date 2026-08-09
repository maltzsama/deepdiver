require "rails_helper"

RSpec.describe ScaleDownJob, type: :job do
  def broken_runtime
    Class.new(FakeTrinoRuntime) do
      def ensure_stopped
        raise "k8s unavailable"
      end
    end.new
  end

  it "does not overwrite a success when the teardown fails" do
    execution = create(:execution_history, status: :success, current_step: :scale_down)
    TrinoRuntime.adapter = broken_runtime

    expect { described_class.perform_now(execution.id) }.to raise_error(RuntimeError, /k8s unavailable/)

    execution.reload
    expect(execution.status).to eq("success")
    expect(execution.error_message).to match(/scale down failed/)
  end

  it "marks a non-successful execution failed on teardown error" do
    execution = create(:execution_history, status: :running, current_step: :scale_down)
    TrinoRuntime.adapter = broken_runtime

    expect { described_class.perform_now(execution.id) }.to raise_error(RuntimeError)

    execution.reload
    expect(execution.status).to eq("failed")
  end

  it "returns silently when the execution was deleted" do
    expect { described_class.perform_now(99_999_999) }.not_to raise_error
  end
end
