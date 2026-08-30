require "rails_helper"

RSpec.describe RefreshStsCredentialsJob, type: :job do
  it "does nothing when no catalogs use STS" do
    create(:catalog, s3_authentication_type: "none")
    projection = instance_double(TrinoCatalogProjection)
    allow(TrinoCatalogProjection).to receive(:new).and_return(projection)
    allow(projection).to receive(:sync_all!)

    described_class.perform_now

    expect(projection).not_to have_received(:sync_all!)
  end

  it "re-syncs all catalogs when at least one uses STS" do
    create(:catalog, :s3_sts)
    projection = instance_double(TrinoCatalogProjection)
    allow(TrinoCatalogProjection).to receive(:new).and_return(projection)
    allow(projection).to receive(:sync_all!)

    materializer = instance_double(TrinoSecretMaterializer)
    allow(TrinoSecretMaterializer).to receive(:new).and_return(materializer)
    allow(materializer).to receive(:materialize!)

    described_class.perform_now

    expect(projection).to have_received(:sync_all!).once
    expect(materializer).to have_received(:materialize!).once
  end
end
