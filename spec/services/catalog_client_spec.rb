require "rails_helper"

RSpec.describe CatalogClient do
  it "propagates a root failure instead of returning an empty list" do
    transport = instance_double(HttpTransport)
    allow(transport).to receive(:get).and_raise(HttpTransport::ApiError.new(404, ""))
    client = NessieCatalogClient.new(create(:catalog, catalog_type: "nessie"), transport:)

    expect { client.namespaces }.to raise_error(HttpTransport::ApiError)
  end
end
