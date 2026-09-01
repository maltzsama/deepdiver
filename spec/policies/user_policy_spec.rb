require "rails_helper"

RSpec.describe UserPolicy, type: :policy do
  let(:admin) { create(:user, role: "admin") }
  let(:viewer) { create(:user, role: "viewer") }

  describe "#update?" do
    it "allows an admin to change another user's role" do
      expect(described_class.new(admin, viewer).update?).to be true
    end

    it "forbids an admin from changing their own role" do
      expect(described_class.new(admin, admin).update?).to be false
    end

    it "forbids a non-admin from changing roles" do
      expect(described_class.new(viewer, admin).update?).to be false
    end
  end
end
