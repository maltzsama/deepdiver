# Mirror of the Baleia plugin registry table (trino_catalog_registry) in
# Postgres. The plugin reads this at Trino boot (Database.java v0.2.1:
# SELECT catalog_name, connector_name, properties::text, JOINed onto
# trino_clusters.name, filtered by enabled).
#
# SECURITY NOTE: The 'properties' JSON column contains Polaris credentials
# in plaintext because the Trino plugin reads it directly from the database.
# This table MUST NOT be exposed via any API, backup copy, or ad-hoc query
# outside the cluster. Restrict DB grants accordingly.
#
# The application writes rows directly here - no catalog_version hash, no
# CREATE CATALOG. 'baleia' is the only allowed writer from the app side; the
# 'trino' value is reserved for the coordinator writing back.
class TrinoCatalogRegistry < ApplicationRecord
  self.table_name = "trino_catalog_registry"

  WRITER = "baleia"
  SYNC_STATUSES = %w[pending synced error].freeze

  belongs_to :trino_cluster, foreign_key: :cluster_id

  validates :catalog_name, presence: true,
            format: { with: Catalog::TRINO_NAME_PATTERN }
  validates :connector_name, presence: true,
            format: { with: Catalog::TRINO_NAME_PATTERN }
  validates :sync_status, inclusion: { in: SYNC_STATUSES }
  validates :updated_by, inclusion: { in: [ WRITER, "trino" ] }
  validate  :catalog_name_not_reserved

  def inspect
    super.gsub(/"properties"=>.*?(?=,|>)/, '"properties"=>[FILTERED]')
  end

  def serializable_hash(options = nil)
    super((options || {}).merge(except: [ :properties ]))
  end

  # Warns on the Errors page if the plugin role is not configured.
  # Fires at most once per deploy (deduped by ErrorEvent rising-edge capture).
  def self.warn_missing_role!
    return if ENV["BALEIA_DB_ROLE"].present?

    ErrorEvent.record(
      catalog: nil, schema: "security", operation: "db-grants",
      source_system: "app", severity: "warning",
      error_class: "UnrestrictedRegistryAccess",
      message: "trino_catalog_registry without dedicated role — see docs/security.md"
    )
  end

  private

  def catalog_name_not_reserved
    return unless catalog_name.in?(Catalog::TRINO_RESERVED)

    errors.add(:catalog_name, :reserved)
  end
end
