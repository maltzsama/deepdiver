require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#compact_number" do
    it "leaves small numbers alone" do
      expect(helper.compact_number(0)).to eq("0")
      expect(helper.compact_number(999)).to eq("999")
    end

    it "formats thousands with one decimal below 10k" do
      expect(helper.compact_number(1000)).to eq("1k")
      expect(helper.compact_number(1100)).to eq("1.1k")
      expect(helper.compact_number(1234)).to eq("1.2k")
      expect(helper.compact_number(9999)).to eq("10k")
    end

    it "formats from 10k with a whole number" do
      expect(helper.compact_number(10_000)).to eq("10k")
      expect(helper.compact_number(12_300)).to eq("12k")
    end
  end

  describe "#active_path?" do
    it "is active only on the root for '/'" do
      helper.request = Struct.new(:path).new("/")
      expect(helper.active_path?("/")).to be(true)

      helper.request = Struct.new(:path).new("/iceberg_tables")
      expect(helper.active_path?("/")).to be(false)
    end

    it "matches nested paths under a section but not sibling sections" do
      helper.request = Struct.new(:path).new("/maintenance_plans/3")
      expect(helper.active_path?("/maintenance_plans")).to be(true)
      expect(helper.active_path?("/maintenance_policies")).to be(false)

      helper.request = Struct.new(:path).new("/maintenance_plans")
      expect(helper.active_path?("/maintenance_plans")).to be(true)
    end
  end
end
