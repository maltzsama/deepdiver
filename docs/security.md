# Security

## trino_catalog_registry plaintext credentials

The `trino_catalog_registry.properties` column contains Trino connector credentials
in **plaintext**. This is intentional: the Baleia Trino plugin reads this column
directly at coordinator boot (`Database.java` v0.2.1) and cannot decrypt
Active Record Encryption values.

### Why not encrypt?

The plugin is a JVM process that connects to the same PostgreSQL database. It
reads `properties::text` with a simple SQL query. Making it decrypt would require
changing the plugin to handle Active Record Encryption — a different project.

### What this means

- **Backups** of `trino_catalog_registry` contain credentials in cleartext.
  Treat backup files with the same care as a secrets file.
- **`to_json` / `as_json`** on this model does **not** include `properties`
  (filtered by `serializable_hash`).
- **`inspect`** masks the column.
- **Ad-hoc SQL queries** (psql, BI tools) will show the plaintext values.

### Required mitigations

1. **Separate database role for the plugin.** The application role must NOT
   be used by the Trino coordinator. Create a read-only role:

   See `db/grants/baleia_reader.sql` for the exact grants.

2. **Restrict backup access.** Backups that include `trino_catalog_registry`
   must be encrypted at rest and access-controlled like any secrets store.

3. **Rotate credentials** when a team member with DB access leaves, or when
   a backup may have been exposed. The CatalogCredential rotation flow
   (Admin UI > Catalogs > Edit > rotate secret) pushes new credentials to
   both `catalog_credentials` (encrypted) and `trino_catalog_registry`
   (plaintext for the plugin).

## Database roles

| Role | Used by | Access |
|------|---------|--------|
| Application role | Rails app | Full CRUD on all tables |
| `baleia_reader` | Trino coordinator plugin | SELECT on `trino_catalog_registry` (limited columns) and `trino_clusters` |

See `db/grants/baleia_reader.sql` for the grant statements.
