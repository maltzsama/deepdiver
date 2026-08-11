# Provisions Trino with the baleia-trino-catalog-store plugin.
#
# The plugin reads the catalogs from trino_catalog_registry at boot. Because
# the engine is ephemeral, the boot happens on every window - there is no
# runtime CREATE CATALOG.
class BaleiaTrinoProvisioner < ChartTrinoProvisioner
  # Syncs the catalog registry (the plugin reads it at boot), then applies the
  # Helm chart so the cluster comes up with the catalog already available.
  def create!
    # The plugin reads at boot. A stale registry means the cluster comes up
    # without the catalog, and maintenance fails with "catalog not found".
    TrinoCatalogProjection.new(cluster_name: cluster_name).sync_all!
    super               # apply the chart, with the plugin already in the image
  end

  private

  # baleia.cluster-name on the plugin side; must match a row in trino_clusters.
  def cluster_name
    ENV.fetch("TRINO_CLUSTER_NAME", "default")
  end
end
