# An application account. Accounts come from the IdP via OIDC or are created
# locally by seeding or invites; roles and suspension are managed in-app.
class User < ApplicationRecord
  # :registerable REMOVED - accounts come from the IdP or are created by seed.
  # With SSO on, public self-registration is an open door.
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable,
         :timeoutable, :lockable,
         :omniauthable, omniauth_providers: %i[openid_connect]

  ROLES = %w[viewer operator admin].freeze
  STATUSES = %w[active invited suspended].freeze

  enum :role, { viewer: 0, operator: 1, admin: 2 }, default: :viewer
  attribute :status, :string, default: "active"

  has_many :role_change_logs, dependent: :destroy
  has_many :memberships, class_name: "TeamMembership", dependent: :destroy
  has_many :teams, through: :memberships
  has_many :invited_users, class_name: "User", foreign_key: "invited_by_id", inverse_of: :invited_by
  belongs_to :invited_by, class_name: "User", optional: true
  belongs_to :suspended_by, class_name: "User", optional: true

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :locale, inclusion: { in: %w[en pt-BR] }
  validates :theme, inclusion: { in: %w[light dark] }

  scope :active, -> { where(status: "active") }

  # Whether the user's account is active.
  # @return [Boolean]
  def active?      = status == "active"
  # Whether the user was invited but has not signed in yet.
  # @return [Boolean]
  def invited?     = status == "invited"
  # Whether the user's account is suspended.
  # @return [Boolean]
  def suspended?   = status == "suspended"

  # Whether the user signed in through the SSO provider.
  # @return [Boolean]
  def sso?
    provider.present?
  end

  # Suspended accounts cannot sign in, even via the IdP. Without this, an
  # OIDC session would keep working after an admin suspends the user.
  def active_for_authentication?
    super && active?
  end

  # Message shown when an inactive user tries to sign in; suspended accounts
  # get a dedicated message.
  # @return [Symbol, String]
  def inactive_message
    suspended? ? :suspended : super
  end

  # Suspend / reactivate with an audit trail.
  def suspend!(by: nil, reason: nil)
    update!(status: "suspended", suspended_at: Time.current, suspended_by_id: by&.id)
  end

  # Reactivates the user's account and clears suspension metadata.
  # @param by [User, nil] the admin performing the reactivation
  def reactivate!(by: nil)
    update!(status: "active", suspended_at: nil, suspended_by_id: nil)
  end

  # Promote / demote a user. Every change is recorded in role_change_logs.
  def change_role!(new_role, changed_by:, reason: nil)
    new_role = new_role.to_s
    return self if role == new_role

    old_role = role
    update!(role: new_role)
    role_change_logs.create!(
      changed_by: changed_by,
      from_role: self.class.roles.fetch(old_role),
      to_role: self.class.roles.fetch(new_role),
      reason: reason
    )
    self
  end

  # Finds or creates the account from what the IdP returned.
  # Role NEVER comes from the IdP by default: promoting to admin is something
  # done locally. New accounts start as viewer.
  def self.from_omniauth(auth)
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    email = auth.info.email
    return nil if email.blank?

    # Only link a pre-existing local account by email when the IdP verified the
    # email. An unverified identity claiming someone else's address must not
    # silently take over an existing account.
    existing = find_by(email: email)
    if existing && !omniauth_email_verified?(auth)
      Rails.logger.warn("from_omniauth: refusing to link #{email} to account #{existing.id} " \
                        "— IdP did not verify the email")
      return nil
    end

    user = existing || User.new(email: email)
    user.provider = auth.provider
    user.uid      = auth.uid
    user.password = Devise.friendly_token(32) if user.new_record?
    user.role   ||= :viewer
    # First SSO login converts an invited account into a live one.
    user.status = "active" if user.invited?
    user.save!
    user
  end

  # Whether the IdP asserted the email address is verified. Accepts the common
  # conventions: info.verified, info.email_verified, or raw_info.email_verified
  # (booleans or "true"/"false" strings). When the IdP sends no verification
  # flag we assume NOT verified — linking an existing account by email is only
  # safe on an explicit assertion.
  #
  # @param auth [OmniAuth::AuthHash] the IdP response
  # @return [Boolean]
  def self.omniauth_email_verified?(auth)
    info = auth.info || {}
    raw  = auth.dig("extra", "raw_info") || {}
    [ info["verified"], info["email_verified"], raw["email_verified"] ]
      .any? { |v| v == true || v == "true" }
  end
end
