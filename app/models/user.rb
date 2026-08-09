class User < ApplicationRecord
  # :registerable REMOVED - accounts come from the IdP or are created by seed.
  # With SSO on, public self-registration is an open door.
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[openid_connect]

  enum :role, { viewer: 0, admin: 1 }

  def admin?
    role == "admin"
  end

  def sso?
    provider.present?
  end

  # Finds or creates the account from what the IdP returned.
  # Role NEVER comes from the IdP by default: promoting to admin is something
  # done locally. New accounts start as viewer.
  def self.from_omniauth(auth)
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    email = auth.info.email
    return nil if email.blank?

    # Link to a pre-existing local account with the same email instead of
    # creating a duplicate.
    user = find_or_initialize_by(email: email)
    user.provider = auth.provider
    user.uid      = auth.uid
    user.password = Devise.friendly_token(32) if user.new_record?
    user.role   ||= :viewer
    user.save!
    user
  end
end
