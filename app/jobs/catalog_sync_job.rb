class CatalogSyncJob < ApplicationJob
  queue_as :sync

  # Lightweight sync: refreshes Iceberg table metadata (last snapshot, health)
  # from the catalog REST APIs. Does not require Trino.
  def perform(catalog_id = nil, force: false)
    catalogs = catalog_id.blank? ? Catalog.all : Catalog.find([ catalog_id ])

    catalogs.each do |catalog|
      CatalogSyncService.new(catalog).sync
    end
  end
end
