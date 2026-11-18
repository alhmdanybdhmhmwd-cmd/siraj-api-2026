# Siraj API

Cloudflare Worker backend for the Siraj application.

## D1 migrations

The Worker expects the D1 schema migrations to be applied before deploying code that uses them.

For the recovery-code feature, the migration is:

- `migrations/0001_recovery_codes.sql`

After authenticating Wrangler with the Cloudflare account that owns the `siraj-db` database, review the target database and apply the migration:

```bash
npx wrangler d1 migrations list siraj-db --remote
npx wrangler d1 migrations apply siraj-db --remote
```

Do not deploy the Worker until the migration has completed successfully. The migration only creates the two recovery-related tables and an index; it does not alter or delete existing user, message, contact, or group data.

## Recovery-code behavior

- New registrations receive a one-time display of a high-entropy recovery code.
- Only a salted SHA-256 digest and salt are stored in D1; the plaintext code is never stored.
- Existing users can rotate/create a code after authenticating and confirming their current password.
- Recovery attempts are rate-limited by normalized account identifier and account ID.
- Recovery codes currently do not expire automatically; they remain valid until consumed or replaced. Users should keep them private and rotate them if exposed.

The Flutter client must securely display and let the user save/copy the code, and must provide the recovery form before this feature is considered ready for release.
