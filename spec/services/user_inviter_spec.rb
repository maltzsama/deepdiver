require "rails_helper"

RSpec.describe UserInviter do
  describe ".call" do
    let(:admin) { create(:user, :admin) }

    it "creates an invited account with a device password" do
      user, error = described_class.call(email: "A@Example.COM", role: "operator", invited_by: admin)

      expect(error).to be_nil
      expect(user.email).to eq("a@example.com")
      expect(user).to be_invited
      expect(user.role).to eq("operator")
      expect(user.invited_by).to eq(admin)
      expect(user.encrypted_password).to be_present
    end

    it "refuses a blank email" do
      user, error = described_class.call(email: "  ", role: "viewer", invited_by: admin)

      expect(user).to be_nil
      expect(error).to eq("Email is required")
    end

    it "refuses an already-active user" do
      active = create(:user, email: "live@example.com")

      user, error = described_class.call(email: active.email, role: "viewer", invited_by: admin)

      expect(user).to eq(active)
      expect(error).to eq("This user is already active")
    end

    it "re-invites a suspended user without resetting their audit trail" do
      user = create(:user, email: "old@example.com", status: "suspended")
      user.update!(suspended_at: 1.week.ago)

      described_class.call(email: user.email, role: "operator", invited_by: admin)

      expect(user.reload).to be_invited
      expect(user.role).to eq("operator")
      expect(user.suspended_at).to be_present
    end
  end
end
