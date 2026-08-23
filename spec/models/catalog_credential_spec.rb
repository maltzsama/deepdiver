require "rails_helper"

RSpec.describe CatalogCredential, type: :model do
  it "rejects secret-looking keys in the properties bag" do
    credential = build(:catalog_credential, auth_method: "none",
                                             properties: { "token" => "smuggled" })

    expect(credential).not_to be_valid
    expect(credential.errors[:properties]).to be_present
  end

  it "allows plain configuration keys in properties" do
    credential = build(:catalog_credential,
                       properties: { "subject_token_type" => "urn:example" })

    expect(credential).to be_valid
  end

  it "requires token_endpoint for the exchange strategy" do
    credential = build(:catalog_credential, auth_method: "oauth2_token_exchange", token_endpoint: nil)

    expect(credential).not_to be_valid
    expect(credential.errors[:token_endpoint]).to be_present
  end

  it "stores the secret encrypted at rest" do
    credential = create(:catalog_credential, auth_method: "bearer_static", secret: "visible-secret")
    raw = ApplicationRecord.connection.select_value(
      "SELECT secret FROM catalog_credentials WHERE id = #{credential.id}"
    )

    expect(raw).not_to include("visible-secret")
    expect(raw).to be_present
  end
end
