require "rails_helper"

RSpec.describe "Teams", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:viewer) { create(:user, role: "viewer") }

  describe "authorization" do
    it "lets an admin manage teams" do
      sign_in admin
      get teams_path

      expect(response).to have_http_status(:ok)
    end

    it "does not let a viewer manage teams" do
      sign_in viewer

      expect {
        get teams_path
        follow_redirect!
      }.not_to raise_error

      expect(response.body).to include("You do not have permission")
    end
  end

  describe "POST /teams" do
    before { sign_in admin }

    it "creates a team with members and catalog scope" do
      user    = create(:user)
      catalog = create(:catalog)

      expect {
        post teams_path,
             params: { team: { name: "Analytics", description: "BI", user_ids: [ user.id ], catalog_ids: [ catalog.id ] } }
      }.to change(Team, :count).by(1)

      team = Team.last
      expect(team.members).to include(user)
      expect(team.catalogs).to include(catalog)
      expect(team).not_to be_scoped_to_all_catalogs
    end

    it "creates a team without catalog scope = acts on all catalogs" do
      post teams_path, params: { team: { name: "Platform" } }

      expect(Team.last).to be_scoped_to_all_catalogs
    end

    it "rejects a blank name" do
      expect {
        post teams_path, params: { team: { name: "" } }
      }.not_to change(Team, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /teams/:id" do
    before { sign_in admin }
    let(:team) { create(:team) }

    it "updates the team" do
      patch team_path(team), params: { team: { description: "New desc" } }

      expect(team.reload.description).to eq("New desc")
      follow_redirect!
      expect(response.body).to include("updated")
    end
  end

  describe "DELETE /teams/:id" do
    before { sign_in admin }

    it "destroys the team and its memberships" do
      team = create(:team)
      create(:team_membership, team:)

      expect {
        delete team_path(team)
      }.to change(Team, :count).by(-1).and change(TeamMembership, :count).by(-1)
    end
  end
end
