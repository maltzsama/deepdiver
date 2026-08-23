# Catalog client for Nessie over its Iceberg REST surface (/iceberg), NOT the
# native /api/v2 trees API - this app only reads metadata, and Iceberg REST is
# what CatalogClient already speaks.
#
# Empirical (0.108.4): GET /iceberg/v1/config returns defaults.prefix = the
# default ref ("prefix-pattern": "{ref}|{warehouse}"); an explicit
# catalogs.nessie_ref replaces that prefix so reads pin a branch. Unknown refs
# answer HTTP 400 on any /v1/{ref}/... path.
class NessieCatalogClient < CatalogClient
  # @return [String] the mount prefix before /v1
  def mount_prefix
    "/iceberg"
  end

  # Nessie defines warehouses server-side and rejects unknown names with 500 -
  # never send one; the configured default answers.
  #
  # @return [nil]
  def config_warehouse = nil
end
