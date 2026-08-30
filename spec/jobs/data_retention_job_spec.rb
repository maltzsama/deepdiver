require "rails_helper"

RSpec.describe DataRetentionJob, type: :job do
  describe "pruning with cascade FK" do
    it "deletes old execution_histories and their steps without FK violation" do
      old_execution = create(:execution_history, created_at: 100.days.ago, status: "success")
      old_step = create(:execution_step, execution_history: old_execution, created_at: 100.days.ago)

      recent_execution = create(:execution_history, created_at: 10.days.ago, status: "success")
      recent_step = create(:execution_step, execution_history: recent_execution, created_at: 10.days.ago)

      described_class.perform_now

      expect(ExecutionHistory.exists?(old_execution.id)).to be(false)
      expect(ExecutionStep.exists?(old_step.id)).to be(false)
      expect(ExecutionHistory.exists?(recent_execution.id)).to be(true)
      expect(ExecutionStep.exists?(recent_step.id)).to be(true)
    end

    it "deletes error_events not seen for the retention window" do
      old = create(:error_event, created_at: 100.days.ago, last_seen_at: 100.days.ago)
      recent = create(:error_event, created_at: 10.days.ago, last_seen_at: 10.days.ago)

      described_class.perform_now

      expect(ErrorEvent.exists?(old.id)).to be(false)
      expect(ErrorEvent.exists?(recent.id)).to be(true)
    end

    it "keeps an old error_event that is still recurring" do
      # ErrorEvent.record dedupes by message: a recurring failure keeps its
      # original created_at and only bumps last_seen_at. Pruning by created_at
      # deleted open errors that were still happening.
      recurring = create(:error_event, created_at: 100.days.ago, last_seen_at: 1.hour.ago,
                                       status: "open", occurrence_count: 42)

      described_class.perform_now

      expect(ErrorEvent.exists?(recurring.id)).to be(true)
    end

    it "deletes old freshness_checks" do
      old = create(:freshness_check, created_at: 40.days.ago)
      recent = create(:freshness_check, created_at: 10.days.ago)

      described_class.perform_now

      expect(FreshnessCheck.exists?(old.id)).to be(false)
      expect(FreshnessCheck.exists?(recent.id)).to be(true)
    end

    it "records an ErrorEvent when a prune fails" do
      allow(ErrorEvent).to receive(:record)

      # Force a failure on execution_histories prune
      allow_any_instance_of(DataRetentionJob).to receive(:prune).and_wrap_original do |original, key, klass|
        raise ActiveRecord::StatementInvalid, "test failure" if key == :execution_histories

        original.call(key, klass)
      end

      expect { described_class.perform_now }.to raise_error(ActiveRecord::StatementInvalid)
      expect(ErrorEvent).to have_received(:record).with(
        hash_including(operation: "data-retention", source_system: "app")
      )
    end
  end

  describe "batch deletion" do
    it "deletes in batches of BATCH_SIZE" do
      records = Array.new(described_class::BATCH_SIZE + 10) do
        create(:error_event, created_at: 100.days.ago, last_seen_at: 100.days.ago)
      end

      described_class.perform_now

      expect(ErrorEvent.where(id: records.map(&:id)).count).to eq(0)
    end
  end

  describe "#retention_cutoff" do
    it "uses the default when env is not set" do
      job = described_class.new
      cutoff = job.send(:retention_cutoff, :error_events)
      expect(cutoff).to be_within(1.day).of(90.days.ago)
    end

    it "honors a valid numeric override" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ERROR_EVENTS_RETENTION_DAYS").and_return("15")
      job = described_class.new
      cutoff = job.send(:retention_cutoff, :error_events)
      expect(cutoff).to be_within(1.day).of(15.days.ago)
    end

    it "falls back to default on non-numeric string" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ERROR_EVENTS_RETENTION_DAYS").and_return("abc")
      job = described_class.new
      cutoff = job.send(:retention_cutoff, :error_events)
      expect(cutoff).to be_within(1.day).of(90.days.ago)
    end

    it "falls back to default on empty string" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ERROR_EVENTS_RETENTION_DAYS").and_return("")
      job = described_class.new
      cutoff = job.send(:retention_cutoff, :error_events)
      expect(cutoff).to be_within(1.day).of(90.days.ago)
    end

    it "falls back to default on zero" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ERROR_EVENTS_RETENTION_DAYS").and_return("0")
      job = described_class.new
      cutoff = job.send(:retention_cutoff, :error_events)
      expect(cutoff).to be_within(1.day).of(90.days.ago)
    end

    it "falls back to default on negative value" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ERROR_EVENTS_RETENTION_DAYS").and_return("-5")
      job = described_class.new
      cutoff = job.send(:retention_cutoff, :error_events)
      expect(cutoff).to be_within(1.day).of(90.days.ago)
    end

    it "never produces a cutoff in the future" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ERROR_EVENTS_RETENTION_DAYS").and_return("abc")
      job = described_class.new
      cutoff = job.send(:retention_cutoff, :error_events)
      expect(cutoff).to be <= Time.current
    end
  end
end
