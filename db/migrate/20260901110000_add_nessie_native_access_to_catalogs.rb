class AddNessieNativeAccessToCatalogs < ActiveRecord::Migration[8.0]
  def change
    # Nessie exposes two independent access models. "rest" (the Iceberg REST
    # surface at /iceberg/v1 with a server-side default warehouse) is the
    # historical default. "native" (/api/v2 with a client-supplied warehouse
    # and authentication.type) is what Iceberg's own NessieCatalog uses; on
    # deployments configured for it the REST surface is dead (HTTP 500).
    add_column :catalogs, :nessie_api_mode, :string, default: "rest", null: false
    # Client-side warehouse location for the native model; ignored for "rest".
    add_column :catalogs, :nessie_warehouse, :string
  end
end
