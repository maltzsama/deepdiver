require "rails_helper"

RSpec.describe "GET /", type: :request do
  let(:user)    { create(:user) }
  let(:catalog) { create(:catalog) }

  before { sign_in user }

  it "counts tables by health status" do
    create_list(:iceberg_table, 2, catalog:, health_status: "critical", health_score: 10)
    create(:iceberg_table, catalog:, health_status: "healthy", health_score: 90)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(assigns(:health_counts)).to include("critical" => 2, "healthy" => 1)
    expect(assigns(:total_tables)).to eq(3)
  end

  it "does not break when there are no tables" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(assigns(:total_tables)).to eq(0)
  end

  it "reports when the last sync happened" do
    create(:iceberg_table, catalog:, metadata_synced_at: 5.seconds.ago)

    get root_path

    expect(assigns(:last_sync_at)).to be_present
    expect(response.body).to match(/Synced less than a minute ago/)
  end

  it "includes tables needing action in the triage list" do
    create(:iceberg_table, catalog:, health_status: "critical",
                           health_score: 20, health_status_changed_at: 2.days.ago)

    get root_path

    expect(assigns(:triage).map(&:table).map(&:health_status)).to eq([ "critical" ])
  end

  it "shows an empty state when nothing needs action" do
    get root_path

    expect(response.body).to include("Nothing needs attention")
  end
end
