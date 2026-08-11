# Refreshes Iceberg table metadata (last snapshot, health) for one or all
# catalogs using the catalog REST APIs, without needing Trino.
class CatalogSyncJob < ApplicationJob
  queue_as :sync

  # Lightweight sync: refreshes Iceberg table metadata (last snapshot, health)
  # from the catalog REST APIs. Does not require Trino.
  # @param catalog_id [Integer, nil] the catalog to sync; nil syncs every catalog.
  # @param force [Boolean] reserved for a forced refresh; currently unused.
  def perform(catalog_id = nil, force: false)
    catalogs = catalog_id.blank? ? Catalog.all : Catalog.find([ catalog_id ])

    catalogs.each do |catalog|
      CatalogSyncService.new(catalog).sync
    end
  end
end
