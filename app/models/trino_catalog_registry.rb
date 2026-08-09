# Mirror of the Baleia plugin registry table (trino_catalog_registry) in
# Postgres. The plugin reads this at Trino boot.
#
# PENDING: the exact schema (column names/types) must come from the plugin
# repo's docker/initdb/01-schema.sql before this model and its migration are
# implemented. The Baleia provisioner is only active behind
# TRINO_PROVISIONER=baleia, so this stays a stub until the schema is confirmed.
class TrinoCatalogRegistry < ApplicationRecord
  def self.upsert_from(catalog)
    raise NotImplementedError, "registry schema pending: read docker/initdb/01-schema.sql from the Baleia repo"
  end
end
