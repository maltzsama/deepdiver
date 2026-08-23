# Credential a catalog uses to authenticate against its endpoint. The secret is
# encrypted so it never leaves the database in plain text.
class CatalogCredential < ApplicationRecord
  AUTH_METHODS = %w[none bearer_static oauth2_client_credentials oauth2_token_exchange].freeze

  # Provider-specific exchange knobs that are NOT secrets. Anything secret-ish
  # found here (or in Catalog.properties) is rejected - secrets have exactly
  # one home: the encrypted `secret` column.
  PROPERTIES_SECRET_KEYS = %w[bearerToken token client_secret subject_token password].freeze

  belongs_to :catalog

  # Never leaves the database in plain text.
  encrypts :secret

  validates :auth_method, inclusion: { in: AUTH_METHODS }
  validates :client_id, presence: true, if: :oauth2?
  validates :token_endpoint, presence: true, if: :token_exchange?
  validates :secret, presence: true, unless: :none?
  validate :properties_carry_no_secrets

  before_save :record_secret_metadata, if: :will_save_change_to_secret?

  # Whether the credential uses OAuth2 client-credentials authentication.
  # @return [Boolean] true when auth_method is "oauth2_client_credentials"
  def oauth2? = auth_method == "oauth2_client_credentials"

  # Whether the credential uses OAuth2 token exchange (RFC 8693), e.g. a Dremio
  # PAT swapped for a short-lived access token at an external token server.
  # @return [Boolean] true when auth_method is "oauth2_token_exchange"
  def token_exchange? = auth_method == "oauth2_token_exchange"

  # Whether the catalog endpoint requires no authentication.
  # @return [Boolean] true when auth_method is "none"
  def none? = auth_method == "none"

  # Whether a secret is currently stored for this credential.
  # @return [Boolean] true when the encrypted secret is present
  def secret_set? = secret.present?

  private

  # Guards the config-only properties bag against secret smuggling.
  def properties_carry_no_secrets
    return unless (properties.keys & PROPERTIES_SECRET_KEYS).any?

    errors.add(:properties, :must_not_hold_secrets)
  end

  # Records when the secret was last set and stores the last four characters of
  # it as a display hint.
  def record_secret_metadata
    self.secret_set_at = Time.current
    self.secret_hint   = secret.to_s.last(4)
  end
end
