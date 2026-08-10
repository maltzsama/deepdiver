require "rails_helper"

RSpec.describe User do
  describe ".from_omniauth" do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: "openid_connect", uid: "abc-123",
        info: { email: "employee@company.com" }
      )
    end

    it "creates the account as viewer" do
      user = described_class.from_omniauth(auth)

      expect(user).to be_persisted
      expect(user.role).to eq("viewer")
      expect(user).to be_sso
    end

    it "is idempotent: a second call does not duplicate" do
      described_class.from_omniauth(auth)

      expect { described_class.from_omniauth(auth) }.not_to change(described_class, :count)
    end

    it "links to an existing local account with the same email" do
      local = create(:user, email: "employee@company.com", role: "admin")

      user = described_class.from_omniauth(auth)

      expect(user.id).to eq(local.id)
      expect(user.uid).to eq("abc-123")
    end

    it "does NOT demote someone who was already admin" do
      create(:user, email: "employee@company.com", role: "admin")

      expect(described_class.from_omniauth(auth).role).to eq("admin")
    end

    it "returns nil when the IdP did not send an email" do
      without_email = OmniAuth::AuthHash.new(
        provider: "openid_connect", uid: "x", info: {}
      )

      expect(described_class.from_omniauth(without_email)).to be_nil
    end

    it "turns an invited account into an active one on first login" do
      create(:user, email: "employee@company.com", status: "invited")

      expect(described_class.from_omniauth(auth).status).to eq("active")
    end
  end

  describe "status" do
    it "defaults to active" do
      expect(create(:user).status).to eq("active")
    end

    it "exposes predicate helpers" do
      user = create(:user)
      expect(user).to be_active
      expect(user).not_to be_invited
      expect(user).not_to be_suspended
    end

    it "is denied authentication while suspended" do
      user = create(:user, :suspended)

      expect(user.active_for_authentication?).to be(false)
      expect(user.inactive_message).to eq(:suspended)
    end
  end

  describe "#suspend!/reactivate!" do
    let(:actor) { create(:user, :admin) }

    it "suspends with an audit trail and re-activates cleanly" do
      user = create(:user)
      user.suspend!(by: actor, reason: "abuse")

      expect(user).to be_suspended
      expect(user.suspended_by).to eq(actor)
      expect(user.suspended_at).to be_present

      user.reactivate!(by: actor)

      expect(user).to be_active
      expect(user.suspended_by).to be_nil
      expect(user.suspended_at).to be_nil
    end
  end

  describe "#change_role!" do
    let(:user)   { create(:user) }
    let(:admin)  { create(:user, :admin) }

    it "updates the role and records a log entry" do
      user.change_role!("admin", changed_by: admin, reason: "promoted")

      expect(user.role).to eq("admin")
      log = user.role_change_logs.last
      expect(log.from_role).to eq(0)
      expect(log.to_role).to eq(2)
      expect(log.changed_by).to eq(admin)
      expect(log.reason).to eq("promoted")
    end

    it "does not log when the role is unchanged" do
      expect(user.change_role!("viewer", changed_by: admin)).to eq(user)
      expect(user.role_change_logs).to be_empty
    end
  end
end
