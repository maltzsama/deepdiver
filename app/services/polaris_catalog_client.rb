# Catalog client for Polaris. Mounts the Iceberg REST surface at /api/catalog;
# the warehouse (Polaris catalog name) rides the /v1/config call, and its
# answer carries the prefix every subsequent path must use.
class PolarisCatalogClient < CatalogClient
  # @return [String] the mount prefix before /v1
  def mount_prefix
    "/api/catalog"
  end

  # Polaris names its warehouses; the config endpoint requires it.
  #
  # @return [String] the Polaris catalog name
  def config_warehouse = catalog.name
end
