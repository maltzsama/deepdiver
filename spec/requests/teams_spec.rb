require "rails_helper"

RSpec.describe "Teams", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:viewer) { create(:user) }

  describe "GET /teams" do
    it "redirects viewers away" do
      sign_in viewer
      get teams_path
      expect(response).to redirect_to(root_path)
    end

    it "lists teams for admins" do
      create(:team, name: "Platform")
      sign_in admin
      get teams_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Platform")
    end
  end

  describe "POST /teams" do
    it "creates a team with members" do
      member = create(:user, :operator)
      sign_in admin

      expect {
        post teams_path, params: { team: { name: "Data Squad", member_ids: [ member.id ] } }
      }.to change(Team, :count).by(1)

      team = Team.last
      expect(team.members).to contain_exactly(member)
      expect(response).to redirect_to(team_path(team))
    end
  end

  describe "PATCH /teams/:id" do
    it "updates members" do
      team = create(:team)
      new_member = create(:user, :admin)
      sign_in admin

      patch team_path(team), params: { team: { name: team.name, member_ids: [ new_member.id ] } }

      expect(team.reload.members).to contain_exactly(new_member)
    end
  end

  describe "DELETE /teams/:id" do
    it "destroys the team but keeps users" do
      membership = create(:team_membership)
      sign_in admin

      expect {
        delete team_path(membership.team)
      }.to change(Team, :count).by(-1).and change(User, :count).by(0)
    end
  end
end
