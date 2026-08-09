# Provisions Trino with the baleia-trino-catalog-store plugin.
#
# The plugin reads the catalogs from trino_catalog_registry at boot. Because
# the engine is ephemeral, the boot happens on every window - there is no
# runtime CREATE CATALOG.
#
# PENDING: registry column names. See the verification command in the change
# request (clone the plugin repo and read docker/initdb/01-schema.sql) before
# implementing project_catalogs!.
class BaleiaTrinoProvisioner < ChartTrinoProvisioner
  def create!
    project_catalogs!   # mirror catalogs -> trino_catalog_registry
    super               # apply the chart, with the plugin already in the image
  end

  private

  def project_catalogs!
    Catalog.includes(:catalog_credential).find_each do |catalog|
      TrinoCatalogRegistry.upsert_from(catalog)
    end
  end
end
