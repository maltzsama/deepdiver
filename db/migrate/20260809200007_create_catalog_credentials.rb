class CreateCatalogCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_credentials do |t|
      t.references :catalog, null: false, foreign_key: true, index: { unique: true }

      # none | bearer_static | oauth2_client_credentials
      t.string :auth_method, null: false, default: "none"

      t.string :client_id
      t.text   :secret                 # encrypted by Active Record
      t.string :scope,       default: "PRINCIPAL_ROLE:ALL"
      t.string :token_path,  default: "/v1/oauth/tokens"

      # Metadata for the UI to show WITHOUT revealing the secret.
      t.datetime :secret_set_at
      t.string   :secret_hint          # last 4 chars, just for confirmation

      # Result of the last connection test.
      t.datetime :verified_at
      t.text     :verification_error

      t.timestamps
    end
  end
end
