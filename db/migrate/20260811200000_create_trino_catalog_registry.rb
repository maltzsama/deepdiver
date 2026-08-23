class CreateTrinoCatalogRegistry < ActiveRecord::Migration[8.1]
  def up
    postgres = connection.adapter_name == "PostgreSQL"
    id_type = postgres ? :uuid : :string
    json_type = postgres ? :jsonb : :json

    create_table :trino_clusters, id: false do |t|
      t.column :id, id_type, null: false, primary_key: true
      t.string :name, null: false, index: { unique: true }
      t.timestamps
    end
    create_table :trino_catalog_registry, primary_key: %i[cluster_id catalog_name] do |t|
      t.column :cluster_id, id_type, null: false
      t.string :catalog_name,   null: false
      t.string :connector_name, null: false
      t.column :properties, json_type, null: false
      t.string :catalog_version
      t.boolean :enabled,     null: false, default: true
      t.string  :sync_status, null: false, default: "pending"
      t.text    :sync_error
      t.string  :updated_by,  null: false, default: "baleia"
      t.datetime :updated_at, null: false, default: -> { "now()" }
    end

    add_foreign_key :trino_catalog_registry, :trino_clusters, column: :cluster_id
    add_index :trino_catalog_registry, :cluster_id,
              where: "enabled", name: "trino_catalog_registry_cluster_enabled_idx"

    # The SAME CHECKs as the plugin. They are the first line of defense: if the
    # application generates something invalid, it fails here and not at Trino
    # boot, where the symptom would be an empty SHOW CATALOGS with no explanation.
    execute name_format_sql
    execute <<~SQL
      ALTER TABLE trino_catalog_registry
        ADD CONSTRAINT trino_catalog_registry_sync_status_format
        CHECK (sync_status IN ('pending', 'synced', 'error'));

      ALTER TABLE trino_catalog_registry
        ADD CONSTRAINT trino_catalog_registry_updated_by_format
        CHECK (updated_by IN ('baleia', 'trino'));
    SQL
  end

  def down
    drop_table :trino_catalog_registry
    drop_table :trino_clusters
  end

  private

  # Postgres has ~ (POSIX regex); SQLite uses GLOB. Both approximate the plugin's
  # '^[a-z][a-z0-9_]{0,62}$' closely enough to block bad rows.
  def name_format_sql
    if connection.adapter_name == "PostgreSQL"
      <<~SQL
        ALTER TABLE trino_catalog_registry
          ADD CONSTRAINT trino_catalog_registry_name_format
          CHECK (catalog_name ~ '^[a-z][a-z0-9_]{0,62}$'
             AND catalog_name NOT IN ('system', 'jmx', 'tpch', 'tpcds', 'memory')
             AND connector_name ~ '^[a-z][a-z0-9_]{0,62}$');
      SQL
    else
      <<~SQL
        ALTER TABLE trino_catalog_registry
          ADD CONSTRAINT trino_catalog_registry_name_format
          CHECK (catalog_name GLOB '[a-z][a-z0-9_]*' AND length(catalog_name) <= 63
             AND catalog_name NOT IN ('system', 'jmx', 'tpch', 'tpcds', 'memory')
             AND connector_name GLOB '[a-z][a-z0-9_]*' AND length(connector_name) <= 63);
      SQL
    end
  end
end
