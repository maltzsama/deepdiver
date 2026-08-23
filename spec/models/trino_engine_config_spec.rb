require "rails_helper"

RSpec.describe TrinoEngineConfig do
  describe ".instance" do
    it "creates a singleton with production defaults on first access" do
      config = described_class.instance

      expect(config).to be_persisted
      expect(config.topology).to eq("cluster")
      expect(config.worker_replicas).to eq(2)
      expect(config.coordinator_cpu).to eq("2")
      expect(config.coordinator_memory).to eq("2Gi")
      expect(config.worker_cpu).to eq("1")
      expect(config.worker_memory).to eq("2Gi")
    end

    it "returns the same row on subsequent access" do
      first = described_class.instance
      first.update!(topology: "single")

      expect(described_class.instance.id).to eq(first.id)
      expect(described_class.instance.topology).to eq("single")
    end
  end

  describe "validations" do
    it "rejects an unknown topology" do
      config = described_class.new(topology: "nope")

      expect(config).not_to be_valid
    end

    it "rejects a negative worker count" do
      config = described_class.new(topology: "cluster", worker_replicas: -1)

      expect(config).not_to be_valid
    end
  end

  describe "#cluster?" do
    it "is true for cluster topology" do
      expect(described_class.new(topology: "cluster").cluster?).to be(true)
    end

    it "is false for single topology" do
      expect(described_class.new(topology: "single").cluster?).to be(false)
    end
  end
end
