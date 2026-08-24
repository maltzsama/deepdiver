# Creates accounts at the "invited" status: the user exists in the directory
# but cannot sign in until their first successful SSO login (from_omniauth
# flips invited -> active). Admins use this to onboard people ahead of time
# and to assign a starting role.
#   UserInviter.call(email: "a@b.c", role: "viewer", invited_by: admin)
# Returns [user, error]; error is nil when the invitation was persisted.
class UserInviter
  # Convenience entry point for creating an invited user.
  #
  # @param email [String] the email to invite
  # @param role [String] the starting role
  # @param invited_by [User, nil] the admin performing the invitation
  # @return [Array(User, String)] the user and error (nil when persisted)
  def self.call(email:, role: "viewer", invited_by: nil)
    new(email: email, role: role, invited_by: invited_by).call
  end

  # Creates the inviter with normalized inputs.
  #
  # @param email [String] the email to invite
  # @param role [String] the starting role
  # @param invited_by [User, nil] the admin performing the invitation
  def initialize(email:, role:, invited_by:)
    @email = email.to_s.strip.downcase
    @role  = role
    @invited_by = invited_by
  end

  # Creates or updates the user as "invited", or returns a validation error.
  #
  # @return [Array(User, String)] the user and error (nil when persisted)
  def call
    return [ nil, "Email is required" ] if @email.blank?

    user = User.find_by(email: @email)
    return [ user, "This user is already active" ] if user&.active?

    user ||= User.new(email: @email)
    user.role = @role
    user.status = "invited"
    user.invited_at ||= Time.current
    user.invited_by_id ||= @invited_by&.id
    user.password = Devise.friendly_token(32) if user.encrypted_password.blank?
    return [ user, user.errors.full_messages.to_sentence ] unless user.save

    [ user, nil ]
  end
end
