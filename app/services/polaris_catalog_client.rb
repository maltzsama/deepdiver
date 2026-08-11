# Catalog client for Polaris, using the /api/catalog/v1 Iceberg REST path prefix.
class PolarisCatalogClient < CatalogClient
  # Polaris' default Iceberg REST path prefix.
  #
  # @return [String] "/api/catalog/v1"
  def default_path_prefix
    "/api/catalog/v1"
  end
end
