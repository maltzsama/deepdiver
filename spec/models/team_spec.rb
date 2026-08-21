require "rails_helper"

RSpec.describe Team, type: :model do
  it "requires a unique name" do
    create(:team, name: "Platform")
    expect(build(:team, name: "Platform")).not_to be_valid
  end

  describe "#responders" do
    it "returns only active admin and operator members" do
      team = create(:team)
      admin    = create(:user, :admin)
      operator = create(:user, :operator)
      viewer   = create(:user)
      suspended = create(:user, :admin, :suspended)

      team.members << admin << operator << viewer << suspended

      expect(team.responders).to contain_exactly(admin, operator)
    end
  end

  it "destroys memberships with the team" do
    team = create(:team)
    create(:team_membership, team: team)

    expect { team.destroy! }.to change(TeamMembership, :count).by(-1)
  end
end
