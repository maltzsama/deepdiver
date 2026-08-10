require "rails_helper"

RSpec.describe "Users", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:viewer) { create(:user, role: "viewer") }

  describe "authorization" do
    it "lets an admin list users" do
      sign_in admin
      get users_path

      expect(response).to have_http_status(:ok)
    end

    it "does not let a viewer list users" do
      sign_in viewer
      expect {
        get users_path
        follow_redirect!
      }.not_to raise_error

      expect(response.body).to include("You do not have permission")
    end
  end

  describe "POST /users" do
    before { sign_in admin }

    it "creates an invited account" do
      expect {
        post users_path, params: { user: { email: "new@example.com", role: "operator" } }
      }.to change(User, :count).by(1)

      user = User.last
      expect(user).to be_invited
      expect(user.role).to eq("operator")
      expect(user.invited_by).to eq(admin)
      follow_redirect!
      expect(response.body).to include("Invited")
    end

    it "refuses a blank email" do
      expect {
        post users_path, params: { user: { email: "", role: "viewer" } }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "re-invites a suspended user without duplicating the account" do
      existing = create(:user, email: "old@example.com", status: "suspended")

      post users_path, params: { user: { email: "old@example.com", role: "viewer" } }

      expect(User.where(email: "old@example.com").count).to eq(1)
      expect(existing.reload).to be_invited
    end
  end

  describe "PATCH /users/:id" do
    before { sign_in admin }
    let(:target) { create(:user, role: "viewer") }

    it "changes the role and records a change log" do
      expect {
        patch user_path(target), params: { user: { role: "admin", reason: "needed for infra" } }
      }.to change(RoleChangeLog, :count).by(1)

      expect(target.reload.role).to eq("admin")
      follow_redirect!
      expect(response.body).to include("Role updated")
    end
  end

  describe "suspension" do
    before { sign_in admin }
    let(:target) { create(:user) }

    it "suspends the target" do
      post suspend_user_path(target)

      expect(target.reload).to be_suspended
      follow_redirect!
      expect(response.body).to include("has been suspended")
    end

    it "does not let an admin suspend themselves" do
      expect {
        post suspend_user_path(admin)
      }.not_to change(admin, :status)
    end
  end
end
