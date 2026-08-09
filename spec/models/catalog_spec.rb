require "rails_helper"

RSpec.describe Catalog do
  describe "#trino_catalog_name" do
    it "derives from the name when there is no override" do
      expect(build(:catalog, name: "Polaris Prod").trino_catalog_name).to eq("polaris_prod")
    end

    it "respects the override" do
      catalog = build(:catalog, name: "Polaris Prod", trino_catalog_name_override: "iceberg")
      expect(catalog.trino_catalog_name).to eq("iceberg")
    end

    it "avoids reserved Trino names" do
      expect(build(:catalog, name: "system").trino_catalog_name).to eq("cat_system")
    end

    it "saves without any Trino information" do
      expect(build(:catalog, name: "Novo", trino_catalog_name_override: nil)).to be_valid
    end
  end
end
