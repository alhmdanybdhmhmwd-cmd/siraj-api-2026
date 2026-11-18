# Siraj API

Cloudflare Worker backend for the Siraj application.

## D1 migrations

The Worker expects the D1 schema migrations to be applied before deploying code that uses them.

For the recovery-code feature, the migration is:

- `migrations/0001_recovery_codes.sql`
- `migrations/0002_recovery_token_revocations.sql`

After authenticating Wrangler with the Cloudflare account that owns the `siraj-db` database, review the target database and apply the migration:

```bash
npx wrangler d1 migrations list siraj-db --remote
npx wrangler d1 migrations apply siraj-db --remote
```

Do not deploy the Worker until the migration has completed successfully. These migrations only create recovery-related tables and indexes; they do not alter or delete existing user, message, contact, or group data.

## Recovery-code behavior

- New registrations receive a one-time display of a high-entropy recovery code.
- Only a salted SHA-256 digest and salt are stored in D1; the plaintext code is never stored.
- Existing users can rotate/create a code after authenticating and confirming their current password.
- Recovery attempts are rate-limited by normalized account identifier and account ID. IP-based limiting is deferred until the Vercel-to-Worker proxy can pass a verifiable client identity.
- Newly issued recovery codes expire automatically after 90 days and can be used only once. Issuing a replacement invalidates the previous code.
- A successful password recovery revokes all previously issued login sessions for that account; the user must sign in again.

The current companion Flutter source includes registration-time code display/copy, a password-recovery form, and authenticated code rotation. These client flows still require end-to-end verification against a deployed Worker after the D1 migration is applied.

## Cloudflare Worker Previews (safe D1 isolation)

The Cloudflare Preview build must **not** bind to the production `siraj-db` database. Create a separate D1 database named `siraj-preview-db` in the Cloudflare account, then add the generated ID to this branch's `wrangler.toml`:

```toml
[[previews.d1_databases]]
binding = "DB"
database_name = "siraj-preview-db"
database_id = "<ID returned by wrangler d1 create>"
```

Create the preview database with:

```bash
npx wrangler d1 create siraj-preview-db
```

Keep the existing top-level `[[d1_databases]]` entry unchanged; it is the production binding. Never copy the production `siraj-db` ID into `previews.d1_databases`. Apply the recovery migration to the preview database before testing the Preview. Production migration and deployment remain separate release steps.
