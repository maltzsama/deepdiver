# Builds the catalog REST client matching a catalog's type (Polaris/Nessie).
class CatalogClientFactory
  # Returns the client for a catalog, selected by its catalog_type.
  #
  # @param catalog [Catalog] the catalog to build a client for
  # @return [CatalogClient] the concrete client for the catalog
  # @raise [ArgumentError] if the catalog type is unsupported
  def self.for(catalog)
    case catalog.catalog_type
    when "polaris" then PolarisCatalogClient.new(catalog)
    when "nessie" then NessieCatalogClient.new(catalog)
    else
      raise ArgumentError, "unsupported catalog type: #{catalog.catalog_type}"
    end
  end
end
