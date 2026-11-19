# Siraj API
Cloudflare Worker backend for Siraj application.

## Recovery-code database migrations

The Worker recovery-code endpoints require these additive D1 migrations:

- `migrations/0001_recovery_codes.sql`
- `migrations/0002_recovery_token_revocations.sql`

Wrangler is configured to discover them through `migrations_dir = "migrations"`. Before any deployment, review the target database and migration plan. Apply migrations only to a dedicated, isolated development/preview D1 database during testing. Do not apply them to the production `siraj-db` or deploy production without explicit release approval.

For a safe preview environment, create a separate D1 database and configure the Preview binding to that database. Never point a preview deployment at the production database. Verify migration status and run integration tests against the isolated database before considering release.

Recovery codes are generated once, stored as salted SHA-256 digests, expire after 90 days, and are single-use. Attempts are rate-limited by normalized identifier and account. Successful password recovery invalidates prior login sessions. The Android registration, recovery, and code-rotation flows still require end-to-end testing.
