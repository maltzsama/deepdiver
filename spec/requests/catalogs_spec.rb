require "rails_helper"

RSpec.describe "Catalog credentials", type: :request do
  let(:admin) { create(:user, :admin) }

  it "does not render the secret in the edit form" do
    catalog = create(:catalog)
    create(:catalog_credential, catalog:, auth_method: "oauth2_client_credentials",
                                client_id: "svc", secret: "super-secret-value")
    sign_in admin

    get edit_catalog_path(catalog)

    expect(response.body).not_to include("super-secret-value")
  end

  it "keeps the current secret when the field is left blank" do
    catalog = create(:catalog)
    cred = create(:catalog_credential, catalog:, auth_method: "oauth2_client_credentials",
                                       client_id: "svc", secret: "original")
    sign_in admin

    patch catalog_path(catalog), params: {
      catalog: { name: catalog.name,
                 catalog_credential_attributes: { id: cred.id, client_id: "svc2", secret: "" } }
    }

    expect(cred.reload.secret).to eq("original")
    expect(cred.client_id).to eq("svc2")
  end
end
