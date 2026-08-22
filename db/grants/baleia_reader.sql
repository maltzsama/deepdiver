-- Read-only role for the Baleia Trino plugin.
-- The coordinator reads trino_catalog_registry at boot to configure catalogs.
-- This role must be separate from the application role.
--
-- Run once during initial setup:
--   psql -f db/grants/baleia_reader.sql
--
-- The password placeholder must be replaced with a real value.

CREATE ROLE baleia_reader LOGIN PASSWORD 'CHANGE_ME';

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM baleia_reader;

GRANT USAGE ON SCHEMA public TO baleia_reader;

GRANT SELECT (cluster_id, catalog_name, connector_name, properties, enabled)
  ON trino_catalog_registry TO baleia_reader;

GRANT SELECT (id, name) ON trino_clusters TO baleia_reader;
