require "rails_helper"

RSpec.describe DrainEngineJob, type: :job do
  let(:concurrent_error) { TrinoEngineSupervisor::ConcurrentTransitionError }

  before do
    allow(TrinoEngineSupervisor).to receive(:broadcast_deferred!)
  end

  describe "#destroy_engine" do
    it "silently returns on ConcurrentTransitionError without recording an error" do
      allow(TrinoProvisioner).to receive(:destroy!)
      allow(TrinoEngineSupervisor).to receive(:finish_stopping!).and_raise(concurrent_error)

      expect(TrinoEngineSupervisor).not_to receive(:transition!)
      expect(ErrorEvent).not_to receive(:record)

      described_class.new.send(:destroy_engine)

      expect(TrinoEngineSupervisor).to have_received(:broadcast_deferred!)
    end

    it "records an ErrorEvent and transitions to failed on a generic error" do
      allow(TrinoProvisioner).to receive(:destroy!)
      allow(TrinoEngineSupervisor).to receive(:finish_stopping!).and_raise(StandardError, "boom")
      allow(ErrorEvent).to receive(:record)
      fake_state = double("state", id: 1, status: "stopping", with_lock: nil)
      allow(TrinoEngineSupervisor).to receive(:state).and_return(fake_state)
      allow(TrinoEngineSupervisor).to receive(:transition!)

      described_class.new.send(:destroy_engine)

      expect(ErrorEvent).to have_received(:record).with(
        hash_including(operation: "engine-drain", source_system: "engine", error_class: "StandardError")
      )
      expect(TrinoEngineSupervisor).to have_received(:broadcast_deferred!)
    end

    it "ensures broadcast_deferred! runs even on failure" do
      allow(TrinoProvisioner).to receive(:destroy!).and_raise(StandardError, "boom")
      allow(TrinoEngineSupervisor).to receive(:finish_stopping!)
      allow(TrinoEngineSupervisor).to receive(:state).and_return(
        double("state", id: 1, status: "stopping", with_lock: nil)
      )
      allow(TrinoEngineSupervisor).to receive(:transition!)
      allow(ErrorEvent).to receive(:record)

      described_class.new.send(:destroy_engine)

      expect(TrinoEngineSupervisor).to have_received(:broadcast_deferred!)
    end
  end
end
