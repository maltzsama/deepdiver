-- Role for the Baleia Trino plugin.
-- The coordinator reads trino_catalog_registry at boot to configure catalogs,
-- and writes back sync_status and catalog_version.
-- This role must be separate from the application role.
--
-- Run once during initial setup:
--   psql -f db/grants/baleia_trino.sql
--
-- The password placeholder must be replaced with a real value.

CREATE ROLE baleia_trino LOGIN PASSWORD 'CHANGE_ME';

REVOKE ALL ON SCHEMA public                  FROM baleia_trino;
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM baleia_trino;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM baleia_trino;

GRANT USAGE  ON SCHEMA public                                  TO baleia_trino;
GRANT SELECT ON trino_clusters                                 TO baleia_trino;
GRANT SELECT, INSERT, UPDATE, DELETE ON trino_catalog_registry TO baleia_trino;
