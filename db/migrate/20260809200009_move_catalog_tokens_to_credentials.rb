class MoveCatalogTokensToCredentials < ActiveRecord::Migration[8.1]
  def up
    Catalog.reset_column_information
    Catalog.find_each do |catalog|
      token = catalog.properties&.dig("bearerToken") || catalog.properties&.dig("token")
      next if token.blank?

      CatalogCredential.create!(catalog: catalog, auth_method: "bearer_static", secret: token)
      catalog.update_columns(properties: catalog.properties.except("bearerToken", "token"))
    end
  end

  def down
    # No way back: the secret now lives encrypted.
    raise ActiveRecord::IrreversibleMigration
  end
end
