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

    it "returns a validation error instead of raising for a malformed email" do
      # save! used to be called here, turning a bad email into a 500 instead
      # of the [user, error] tuple the controller expects.
      user, error = described_class.call(email: "not-an-email", role: "viewer", invited_by: admin)

      expect(user).to be_present
      expect(user).not_to be_persisted
      expect(error).to match(/email/i)
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

    it "refuses to re-invite a suspended user, requiring reactivation instead" do
      user = create(:user, email: "old@example.com", status: "suspended")
      user.update!(suspended_at: 1.week.ago)

      invited, error = described_class.call(email: user.email, role: "operator", invited_by: admin)

      expect(invited).to eq(user)
      expect(error).to eq("This user is suspended; reactivate them instead")
      expect(user.reload).to be_suspended
      expect(user.role).not_to eq("operator")
    end
  end
end
