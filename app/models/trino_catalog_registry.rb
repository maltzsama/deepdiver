# Mirror of the Baleia plugin registry table (trino_catalog_registry) in
# Postgres. The plugin reads this at Trino boot (Database.java v0.2.1:
# SELECT catalog_name, connector_name, properties::text, JOINed onto
# trino_clusters.name, filtered by enabled).
#
# The application writes rows directly here - no catalog_version hash, no
# CREATE CATALOG. 'baleia' is the only allowed writer from the app side; the
# 'trino' value is reserved for the coordinator writing back.
class TrinoCatalogRegistry < ApplicationRecord
  self.table_name = "trino_catalog_registry"

  WRITER = "baleia"
  SYNC_STATUSES = %w[pending synced error].freeze

  belongs_to :trino_cluster, foreign_key: :cluster_id

  validates :catalog_name, presence: true
  validates :connector_name, presence: true
  validates :sync_status, inclusion: { in: SYNC_STATUSES }
  validates :updated_by, inclusion: { in: [ WRITER, "trino" ] }
end
