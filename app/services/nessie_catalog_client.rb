# Catalog client for Nessie, using the /api/v1 Iceberg REST path prefix.
class NessieCatalogClient < CatalogClient
  # Nessie's default Iceberg REST path prefix.
  #
  # @return [String] "/api/v1"
  def default_path_prefix
    "/api/v1"
  end
end
