# Siraj API
Cloudflare Worker backend for Siraj application.

## Recovery-code database migrations

The Worker recovery-code endpoints require these additive D1 migrations:

- `migrations/0001_recovery_codes.sql`

Wrangler is configured to discover them through `migrations_dir = "migrations"`. Before any deployment, review the target database and migration plan. Apply migrations only to a dedicated, isolated development/preview D1 database during testing. Do not apply them to the production `siraj-db` or deploy production without explicit release approval.

For a safe preview environment, create a separate D1 database and configure the Preview binding to that database. Never point a preview deployment at the production database. Verify migration status and run integration tests against the isolated database before considering release.

Recovery codes are generated once, stored as salted SHA-256 digests, expire after 90 days, and are single-use. Attempts are rate-limited by normalized identifier and account. Successful password recovery invalidates prior login sessions. The Android registration, recovery, and code-rotation flows still require end-to-end testing.

## Database schema status

The recovery-code migration is present, but this repository does not currently include authoritative base migrations for `users`, `friendships`, or `messages`. Review [the database schema audit](docs/database-schema-audit-2026-11-19.md) before attempting D1 integration tests. Do not use the production D1 binding for testing, and do not create a guessed base schema.


## Production vs Preview migration isolation

The default `wrangler.toml` points only to `migrations/production`, which currently contains the additive recovery-code and revoked-session migrations. The broader `migrations/` directory is the isolated Preview/test fixture and must be used only with `wrangler.test.toml` or `wrangler.fallback.test.toml`. It includes Preview-only core-schema and feature fixtures; never point the production Worker at that directory or apply it to `siraj-db`. No production migration has been applied as part of this audit.
