# Credential a catalog uses to authenticate against its endpoint. The secret is
# encrypted so it never leaves the database in plain text.
class CatalogCredential < ApplicationRecord
  AUTH_METHODS = %w[none bearer_static oauth2_client_credentials].freeze

  belongs_to :catalog

  # Never leaves the database in plain text.
  encrypts :secret

  validates :auth_method, inclusion: { in: AUTH_METHODS }
  validates :client_id, presence: true, if: :oauth2?
  validates :secret, presence: true, unless: :none?

  before_save :record_secret_metadata, if: :will_save_change_to_secret?

  # Whether the credential uses OAuth2 client-credentials authentication.
  # @return [Boolean] true when auth_method is "oauth2_client_credentials"
  def oauth2? = auth_method == "oauth2_client_credentials"

  # Whether the catalog endpoint requires no authentication.
  # @return [Boolean] true when auth_method is "none"
  def none? = auth_method == "none"

  # Whether a secret is currently stored for this credential.
  # @return [Boolean] true when the encrypted secret is present
  def secret_set? = secret.present?

  private

  # Records when the secret was last set and stores the last four characters of
  # it as a display hint.
  def record_secret_metadata
    self.secret_set_at = Time.current
    self.secret_hint   = secret.to_s.last(4)
  end
end
