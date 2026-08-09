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

  it "excludes tables without a score from the worst-health list" do
    com_score = create(:iceberg_table, catalog:, health_score: 30, health_status: "critical")
    create(:iceberg_table, catalog:, health_score: nil, health_status: "unknown")

    get root_path

    expect(assigns(:worst_health_tables)).to contain_exactly(com_score)
  end

  it "reports when the last sync happened" do
    create(:iceberg_table, catalog:)

    get root_path

    expect(assigns(:last_sync_at)).to be_present
    expect(response.body).to include("Not real-time")
  end
end
