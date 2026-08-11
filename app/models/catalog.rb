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
  validates :endpoint, presence: true
  validate :trino_catalog_name_is_valid

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
end
