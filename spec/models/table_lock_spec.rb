require "rails_helper"

RSpec.describe TableLock do
  let(:table) { create(:iceberg_table) }

  it "blocks a second execution on the SAME table" do
    first = create(:execution_history, iceberg_table: table)
    second = create(:execution_history, iceberg_table: table)

    expect(described_class.acquire(first)).to be(true)
    expect(described_class.acquire(second)).to be(false)
  end

  it "allows executions on different tables" do
    other = create(:iceberg_table)

    expect(described_class.acquire(create(:execution_history, iceberg_table: table))).to be(true)
    expect(described_class.acquire(create(:execution_history, iceberg_table: other))).to be(true)
  end

  it "frees the lock of an execution that already finished" do
    execution = create(:execution_history, iceberg_table: table, status: :running)
    described_class.acquire(execution)
    execution.update!(status: :failed)

    expect { described_class.reap_stale! }.to change(described_class, :count).by(-1)
  end
end
