class AddNessieRefAndFixTokenPath < ActiveRecord::Migration[8.1]
  def change
    # Which Nessie ref (branch/tag) the app reads. Nullable: only meaningful
    # for catalog_type = "nessie". When absent the server default branch is
    # used - and that is exactly the silent-divergence risk against Trino.
    add_column :catalogs, :nessie_ref, :string

    # polaris:latest moved the OAuth token endpoint from /v1/oauth/tokens
    # (deprecated in Iceberg 1.6, removed in newer servers) to
    # /api/catalog/v1/oauth/tokens. Old rows keep a dead path.
    change_column_default :catalog_credentials, :token_path, from: "/v1/oauth/tokens", to: "/api/catalog/v1/oauth/tokens"
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE catalog_credentials SET token_path = '/api/catalog/v1/oauth/tokens'
          WHERE token_path = '/v1/oauth/tokens' AND auth_method = 'oauth2_client_credentials'
        SQL
      end
    end
  end
end
