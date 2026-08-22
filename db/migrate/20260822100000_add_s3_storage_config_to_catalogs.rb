class AddS3StorageConfigToCatalogs < ActiveRecord::Migration[8.1]
  def change
    add_column :catalogs, :s3_authentication_type, :string, default: "none", null: false
    add_column :catalogs, :s3_endpoint, :string
    add_column :catalogs, :s3_access_key, :string
    add_column :catalogs, :s3_secret_key, :string
    add_column :catalogs, :s3_role_arn, :string
    add_column :catalogs, :s3_external_id, :string
    add_column :catalogs, :s3_region, :string, default: "us-east-1"
  end
end
