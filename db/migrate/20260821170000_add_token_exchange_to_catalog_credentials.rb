class AddTokenExchangeToCatalogCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_credentials, :token_endpoint, :string
    add_column :catalog_credentials, :oauth_scope, :string
    # Provider-specific NON-secret knobs (subject_token_type, exchange client
    # id overrides). Secrets live only in the encrypted `secret` column.
    add_column :catalog_credentials, :properties, :json, default: {}
  end
end
