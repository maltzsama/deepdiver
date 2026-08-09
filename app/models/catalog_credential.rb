class CatalogCredential < ApplicationRecord
  AUTH_METHODS = %w[none bearer_static oauth2_client_credentials].freeze

  belongs_to :catalog

  # Never leaves the database in plain text.
  encrypts :secret

  validates :auth_method, inclusion: { in: AUTH_METHODS }
  validates :client_id, presence: true, if: :oauth2?
  validates :secret, presence: true, unless: :none?

  before_save :record_secret_metadata, if: :will_save_change_to_secret?

  def oauth2? = auth_method == "oauth2_client_credentials"

  def none? = auth_method == "none"

  def secret_set? = secret.present?

  private

  def record_secret_metadata
    self.secret_set_at = Time.current
    self.secret_hint   = secret.to_s.last(4)
  end
end
