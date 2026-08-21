# A data catalog registered in the application and provisioned into Trino.
# Holds the catalog type, endpoint, and connection credential, and derives a
# valid Trino catalog name from the record name.
class Catalog < ApplicationRecord
  CATALOG_TYPES = %w[polaris nessie].freeze

  # Mirrors CatalogRow.java v0.2.1 and the trino_catalog_registry CHECK. Any
  # drift here makes the INSERT fail with a constraint violation whose message
  # does not help whoever registered the catalog.
  TRINO_NAME_PATTERN = /\A[a-z][a-z0-9_]{0,62}\z/
  TRINO_RESERVED = %w[system jmx tpch tpcds memory].freeze
  TRINO_NAME_MAX = 63

  has_many :iceberg_tables, dependent: :destroy
  has_one :catalog_credential, dependent: :destroy
  accepts_nested_attributes_for :catalog_credential

  validates :name, presence: true, uniqueness: true
  validates :catalog_type, presence: true, inclusion: { in: CATALOG_TYPES }
  validates :endpoint, presence: true, format: { with: /\Ahttps?:\/\//i, message: :must_be_http }
  validate :trino_catalog_name_is_valid
  validate :endpoint_not_internal

  # Name of the catalog inside Trino. Derived from the record name, because
  # the application provisions Trino itself. The override exists for
  # when the name is not a valid identifier or collides.
  def trino_catalog_name
    trino_catalog_name_override.presence || derived_trino_catalog_name
  end

  # Derives a valid Trino catalog name from the record name, slugifying it and
  # prefixing names that start with a digit or collide with a reserved word.
  # @return [String] the derived, truncated catalog name
  def derived_trino_catalog_name
    slug = name.to_s.downcase
               .gsub(/[^a-z0-9_]/, "_")
               .gsub(/_+/, "_")
               .gsub(/\A_+|_+\z/, "")

    # Must start with a letter: prefix when it starts with a digit or is empty.
    slug = "cat_#{slug}" unless slug.match?(/\A[a-z]/)

    # Trino reserved: prefix instead of failing, so registration does not get
    # stuck on a name the person chose without knowing the restriction.
    slug = "cat_#{slug}" if TRINO_RESERVED.include?(slug)

    slug.first(TRINO_NAME_MAX)
  end

  # Human-readable representation of the catalog.
  # @return [String] the catalog name
  def to_s
    name
  end

  # Makes a real call and returns what happened, for the "Test" button.
  def verify_connection!
    CatalogClientFactory.for(self).namespaces
    catalog_credential&.update!(verified_at: Time.current, verification_error: nil)
    { ok: true }
  rescue StandardError => e
    catalog_credential&.update!(verified_at: Time.current, verification_error: e.message)
    { ok: false, error: e.message }
  end

  private

  # Validates the EFFECTIVE value - derived or override. Errors surface on the
  # form, not as a CHECK violation at provisioning time.
  def trino_catalog_name_is_valid
    effective = trino_catalog_name

    unless effective.match?(TRINO_NAME_PATTERN)
      errors.add(:trino_catalog_name_override,
                 I18n.t("activerecord.errors.models.catalog.attributes.trino_catalog_name_override.invalid_format",
                        max: TRINO_NAME_MAX, derived: effective))
      return
    end

    return unless TRINO_RESERVED.include?(effective)

    errors.add(:trino_catalog_name_override,
               I18n.t("activerecord.errors.models.catalog.attributes.trino_catalog_name_override.reserved",
                       name: effective, reserved: TRINO_RESERVED.join(", ")))
  end

  BLOCKED_HOSTS = %w[localhost 127.0.0.1 0.0.0.0 169.254.169.254 ::1 metadata.google.internal kubernetes.default.svc].freeze
  BLOCKED_PREFIXES = %w[10. 172.16. 172.17. 172.18. 172.19. 172.20. 172.21. 172.22. 172.23. 172.24. 172.25. 172.26. 172.27. 172.28. 172.29. 172.30. 172.31. 192.168. fd00: fe80:].freeze

  def endpoint_not_internal
    return if endpoint.blank?

    begin
      uri = URI.parse(endpoint)
      host = uri.host.to_s.downcase
    rescue URI::InvalidURIError
      errors.add(:endpoint, :invalid_url)
      return
    end

    return unless BLOCKED_HOSTS.include?(host) || BLOCKED_PREFIXES.any? { |p| host.start_with?(p) }

    errors.add(:endpoint, :blocked_internal)
  end
end
