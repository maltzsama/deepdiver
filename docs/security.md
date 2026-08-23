# Security

## Catalog credentials

Catalog credentials are stored in two places:

1. **`catalog_credentials.secret`** — encrypted via Active Record Encryption,
   never leaves the database in plaintext.

2. **Kubernetes Secret** (`<release>-trino-catalog-secrets`) — materialized by
   `TrinoSecretMaterializer` with Base64-encoded values. The Trino plugin
   mounts this at `/etc/baleia/secrets` and reads credentials from files.

The `trino_catalog_registry.properties` column contains **references** to the
Secret files, not plaintext values:

```
"iceberg.rest-catalog.oauth2.credential": "@baleia-secret[file:catalog-42-iceberg_rest_catalog_oauth2_credential]"
```

### How it works

1. `TrinoCatalogProjection` writes `@baleia-secret[file:...]` references into
   `trino_catalog_registry.properties`.
2. `TrinoSecretMaterializer` creates/updates a Kubernetes Secret with the
   actual credential values from `CatalogCredential` and `Catalog`.
3. The Trino plugin reads the registry, resolves each `@baleia-secret` reference
   by reading the corresponding file from the mounted Secret.

### Why not encrypt in the database?

The Baleia plugin is a JVM process that reads `trino_catalog_registry` via
SQL. It cannot decrypt Active Record Encryption values. The file-based
secret approach keeps credentials out of the database while remaining
compatible with the plugin.

## Database roles

| Role | Used by | Access |
|------|---------|--------|
| Application role | Rails app | Full CRUD on all tables |
| `baleia_trino` | Trino coordinator plugin | SELECT on `trino_clusters`; SELECT, INSERT, UPDATE, DELETE on `trino_catalog_registry` |

See `db/grants/baleia_trino.sql` for the grant statements.

## Credential rotation

When a catalog credential is rotated (Admin UI > Catalogs > Edit > rotate secret):

1. The new secret is saved encrypted in `catalog_credentials.secret`.
2. On next sync, `TrinoSecretMaterializer` updates the Kubernetes Secret.
3. `TrinoCatalogProjection` writes the new `@baleia-secret` reference.
4. The Trino plugin picks up the change on next catalog reload (no restart needed).

**Important:** Credentials that were in plaintext in older database versions
may still exist in WAL, replicas, and backups. Rotate credentials if a backup
may have been exposed.
