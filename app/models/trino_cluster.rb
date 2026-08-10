# Trino cluster the Baleia catalog-store plugin boots against. The plugin JOINs
# trino_catalog_registry onto trino_clusters.name at boot; without the matching
# row, the coordinator loads ZERO catalogs silently.
class TrinoCluster < ApplicationRecord
  has_many :trino_catalog_registry_entries,
           class_name: "TrinoCatalogRegistry",
           foreign_key: :cluster_id,
           dependent: :destroy

  validates :name, presence: true, uniqueness: true

  before_create :assign_id

  private

  # Postgres fills the uuid via gen_random_uuid; SQLite (dev/test) has no
  # default, so the application generates it.
  def assign_id
    self.id ||= SecureRandom.uuid
  end
end
