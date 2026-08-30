# Periodically re-syncs Trino catalog properties so that STS temporary
# credentials (which expire after ~1 hour) stay fresh. Without this job,
# Trino loses S3 access when the token expires and the engine was not
# restarted.
class RefreshStsCredentialsJob < ApplicationJob
  queue_as :default

  # Only refreshes when at least one catalog uses STS. No-op otherwise.
  def perform
    return unless Catalog.where(s3_authentication_type: "sts").exists?

    catalogs = Catalog.includes(:catalog_credential)
    TrinoCatalogProjection.new.sync_all!
    TrinoSecretMaterializer.new.materialize!(catalogs)
  end
end
