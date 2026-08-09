class Catalog < ApplicationRecord
  CATALOG_TYPES = %w[polaris nessie].freeze

  # Names that are not valid (or not allowed) as Trino catalog names.
  TRINO_RESERVED = %w[system information_schema jmx tpch].freeze

  has_many :iceberg_tables, dependent: :destroy
  has_one :catalog_credential, dependent: :destroy
  accepts_nested_attributes_for :catalog_credential

  validates :name, presence: true, uniqueness: true
  validates :catalog_type, presence: true, inclusion: { in: CATALOG_TYPES }
  validates :endpoint, presence: true

  # Name of the catalog inside Trino. Derived from the record name, because
  # the application provisions Trino (see Phase B). The override exists for
  # when the name is not a valid identifier or collides.
  def trino_catalog_name
    trino_catalog_name_override.presence || derived_trino_catalog_name
  end

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

  def derived_trino_catalog_name
    slug = name.to_s.downcase.gsub(/[^a-z0-9_]/, "_").gsub(/_+/, "_").delete_prefix("_")
    slug = "cat_#{slug}" if slug.blank? || slug.start_with?(/\d/) || TRINO_RESERVED.include?(slug)
    slug
  end
end
