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
  end
end
