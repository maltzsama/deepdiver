require "rails_helper"

RSpec.describe Team do
  describe "validations" do
    it "requires a unique name" do
      create(:team, name: "Analytics")
      expect(build(:team, name: "Analytics")).not_to be_valid
    end
  end

  describe "#scoped_to_all_catalogs?" do
    it "is true when no catalog scope is configured" do
      expect(create(:team)).to be_scoped_to_all_catalogs
    end

    it "is false when catalog scopes exist" do
      team = create(:team)
      create(:team_catalog_scope, team:)

      expect(team).not_to be_scoped_to_all_catalogs
    end
  end

  describe "#manages?" do
    let(:team)    { create(:team) }
    let(:catalog) { create(:catalog) }

    it "manages every catalog when unscoped" do
      expect(team.manages?(catalog)).to be(true)
    end

    it "manages only the scoped catalogs" do
      create(:team_catalog_scope, team:, catalog:)
      other = create(:catalog)

      expect(team.manages?(catalog)).to be(true)
      expect(team.manages?(other)).to be(false)
    end
  end

  describe "associations" do
    it "cleans up memberships and scopes on destroy" do
      team = create(:team)
      create(:team_membership, team:)
      create(:team_catalog_scope, team:)

      expect { team.destroy! }
        .to change(TeamMembership, :count).by(-1)
        .and change(TeamCatalogScope, :count).by(-1)
    end
  end
end
