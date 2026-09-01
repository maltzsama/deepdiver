require "rails_helper"

RSpec.describe CatalogClientFactory do
  it "selects the native Nessie client when nessie_api_mode is native" do
    catalog = create(:catalog, catalog_type: "nessie", nessie_api_mode: "native",
                               nessie_warehouse: "s3://bucket/")

    expect(described_class.for(catalog)).to be_a(NessieNativeCatalogClient)
  end

  it "selects the REST Nessie client by default" do
    catalog = create(:catalog, catalog_type: "nessie")

    expect(described_class.for(catalog)).to be_a(NessieCatalogClient)
  end

  it "selects the Polaris client for polaris catalogs" do
    catalog = create(:polaris_catalog)

    expect(described_class.for(catalog)).to be_a(PolarisCatalogClient)
  end
end
