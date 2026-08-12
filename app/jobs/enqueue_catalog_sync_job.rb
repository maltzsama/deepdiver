# Recurring entry point (see config/recurring.yml) that keeps the catalog
# metadata in sync: enqueues a lightweight refresh of every catalog every 6
# hours, so tables dropped in the catalogs are soft-deleted locally.
class EnqueueCatalogSyncJob < ApplicationJob
  queue_as :sync

  # Enqueues a full catalog sync (all catalogs) through the existing job.
  def perform
    CatalogSyncJob.perform_later
  end
end
