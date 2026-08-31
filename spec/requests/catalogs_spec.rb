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

  it "builds a catalog credential so the new form can define authentication" do
    sign_in admin

    get new_catalog_path

    expect(response.body).to include('name="catalog[catalog_credential_attributes][auth_method]"')
    expect(response.body).to include("oauth2_client_credentials")
  end

  it "syncs a catalog (admin)" do
    catalog = create(:catalog)
    sign_in admin

    expect(MaintenanceOrchestrator).to receive(:sync_catalog).with(catalog.id)

    post sync_catalog_path(catalog)

    expect(response).to redirect_to(catalog_path(catalog))
  end

  it "verifies a catalog connection (admin)" do
    catalog = create(:catalog)
    sign_in admin

    allow(Catalog).to receive(:find).with(catalog.id.to_s).and_return(catalog)
    expect(catalog).to receive(:verify_connection!).and_return({ ok: true, namespace_count: 3 })

    post verify_catalog_path(catalog)

    expect(response).to redirect_to(catalog_path(catalog))
    expect(flash[:notice]).to include("3 namespace(s)")
  end

  it "rejects sync for a non-admin" do
    user = create(:user)
    catalog = create(:catalog)
    sign_in user

    post sync_catalog_path(catalog)

    expect(response).to redirect_to(root_path)
  end

  it "shows only active tables by default and includes inactive on request" do
    admin = create(:user, :admin)
    sign_in admin
    catalog = create(:catalog)
    active = create(:iceberg_table, catalog:, namespace: "bronze", name: "kept")
    dropped = create(:iceberg_table, catalog:, namespace: "silver", name: "gone")
    dropped.deactivate!

    get catalog_path(catalog)
    expect(response.body).to include("kept")
    expect(response.body).not_to include("gone")

    get catalog_path(catalog, inactive: "1")
    expect(response.body).to include("kept")
    expect(response.body).to include("gone")
    expect(response.body).to include("inactive")
    expect(active).to be_active
  end
end
