require "rails_helper"

RSpec.describe Catalog, "#derived_trino_catalog_name" do
  def derived(name) = build(:catalog, name:).derived_trino_catalog_name

  describe "#trino_catalog_name" do
    it "derives from the name when there is no override" do
      expect(build(:catalog, name: "Polaris Prod").trino_catalog_name).to eq("polaris_prod")
    end

    it "respects the override" do
      catalog = build(:catalog, name: "Polaris Prod", trino_catalog_name_override: "iceberg")
      expect(catalog.trino_catalog_name).to eq("iceberg")
    end

    it "saves without any Trino information" do
      expect(build(:catalog, name: "Novo", trino_catalog_name_override: nil)).to be_valid
    end
  end

  it "converts to a valid slug" do
    expect(derived("Polaris Prod")).to eq("polaris_prod")
  end

  it "prefixes a name starting with a digit" do
    expect(derived("2024 warehouse")).to eq("cat_2024_warehouse")
  end

  it "prefixes every reserved plugin name" do
    %w[system jmx tpch tpcds memory].each do |reserved|
      expect(derived(reserved)).to eq("cat_#{reserved}")
    end
  end

  it "respects the 63-character limit" do
    expect(derived("a" * 200).length).to eq(63)
  end

  it "does not leave underscores at the edges" do
    expect(derived("__meu catálogo__")).to eq("meu_cat_logo")
  end

  it "never produces an empty name" do
    expect(derived("!!!")).to eq("cat_")
  end

  it "matches the plugin pattern for every result" do
    [ "Polaris Prod", "2024", "system", "!!!", "a" * 200, "__x__" ].each do |input|
      expect(derived(input)).to match(described_class::TRINO_NAME_PATTERN)
    end
  end

  it "rejects an invalid override on the form, not at INSERT" do
    catalog = build(:catalog, name: "ok", trino_catalog_name_override: "Não-Vale")

    expect(catalog).not_to be_valid
    expect(catalog.errors[:trino_catalog_name_override].join).to include("lowercase letter")
  end

  it "rejects a reserved effective name" do
    catalog = build(:catalog, name: "ok", trino_catalog_name_override: "system")

    expect(catalog).not_to be_valid
    expect(catalog.errors[:trino_catalog_name_override].join).to include("reserved")
  end

  it "localizes the validation error" do
    catalog = build(:catalog, name: "ok", trino_catalog_name_override: "Não-Vale")
    I18n.with_locale("pt-BR") do
      expect(catalog).not_to be_valid
      expect(catalog.errors[:trino_catalog_name_override].join).to include("letra minúscula")
    end
  end
end
