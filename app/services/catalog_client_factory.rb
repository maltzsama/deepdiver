class CatalogClientFactory
  def self.for(catalog)
    case catalog.catalog_type
    when "polaris" then PolarisCatalogClient.new(catalog)
    when "nessie" then NessieCatalogClient.new(catalog)
    else
      raise ArgumentError, "unsupported catalog type: #{catalog.catalog_type}"
    end
  end
end
