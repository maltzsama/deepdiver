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

RSpec.describe "Catalog properties secret guard", type: :model do
  it "rejects secret keys smuggled into the config bag" do
    catalog = build(:catalog, properties: { "bearerToken" => "leak-me" })

    expect(catalog).not_to be_valid
    expect(catalog.errors[:properties]).to be_present
  end

  it "accepts configuration keys" do
    expect(build(:catalog, properties: { "path_prefix" => "/iceberg" })).to be_valid
  end
end

RSpec.describe "Catalog nessie_ref", type: :model do
  it "accepts a ref on nessie catalogs" do
    expect(build(:catalog, catalog_type: "nessie", nessie_ref: "etl_dev")).to be_valid
  end

  it "rejects a ref on polaris catalogs" do
    catalog = build(:polaris_catalog, nessie_ref: "main")

    expect(catalog).not_to be_valid
    expect(catalog.errors[:nessie_ref]).to be_present
  end

  it "rejects ref-shaped garbage" do
    expect(build(:catalog, catalog_type: "nessie", nessie_ref: "bad ref!")).not_to be_valid
  end

  it "allows a blank ref (server default)" do
    expect(build(:catalog, catalog_type: "nessie", nessie_ref: nil)).to be_valid
  end
end

RSpec.describe "Catalog S3 config", type: :model do
  it "allows none without credentials" do
    expect(build(:catalog, s3_authentication_type: "none")).to be_valid
  end

  it "requires access_key and secret_key for static" do
    catalog = build(:catalog, :s3_static, s3_access_key: nil, s3_secret_key: nil)

    expect(catalog).not_to be_valid
    expect(catalog.errors[:s3_access_key]).to be_present
    expect(catalog.errors[:s3_secret_key]).to be_present
  end

  it "requires access_key, secret_key, and role_arn for sts" do
    catalog = build(:catalog, :s3_sts, s3_access_key: nil, s3_secret_key: nil, s3_role_arn: nil)

    expect(catalog).not_to be_valid
    expect(catalog.errors[:s3_access_key]).to be_present
    expect(catalog.errors[:s3_secret_key]).to be_present
    expect(catalog.errors[:s3_role_arn]).to be_present
  end

  it "accepts a valid static config" do
    expect(build(:catalog, :s3_static)).to be_valid
  end

  it "accepts a valid sts config" do
    expect(build(:catalog, :s3_sts)).to be_valid
  end

  describe "#resolve_s3_credentials" do
    it "returns an empty hash for an unrecognized authentication type instead of nil" do
      # s3_authentication_type is validated + defaulted, so this is normally
      # unreachable - but callers do props.merge!(resolve_s3_credentials), and
      # merge!(nil) raises TypeError.
      catalog = build(:catalog, s3_authentication_type: "none")
      catalog.s3_authentication_type = "unknown"

      expect(catalog.resolve_s3_credentials).to eq({})
    end
  end
end
