# Database schema audit — 2026-11-19

## Scope and safety

This audit inspects the Worker SQL and the migrations currently present on
`barq/development-2026-11-19`. It does not connect to D1, create a database,
apply a migration, or change production data.

## Current migration coverage

The repository currently contains only:

- `migrations/0001_recovery_codes.sql`: `recovery_codes`,
  `recovery_rate_limits`, and
  `idx_recovery_rate_limits_window`.

The recovery migration references `users(id)`; therefore the application
base schema must exist before this migration is applied. The SQLite migration
smoke test creates a minimal `users` table as a test prerequisite. It does
not prove that the complete application schema is deployable.

## Tables referenced by Worker SQL

| Table | Current schema source | Notes |
| --- | --- | --- |
| `users` | Not defined in this repository's migrations | Required base table; columns used include `id`, `username`, `display_name`, `password_hash`, `password_salt`, `phone`. |
| `friendships` | Not defined in this repository's migrations | Used by direct contact/friendship checks and media authorization; required columns include `user_id`, `friend_id`. |
| `messages` | Not defined in this repository's migrations | Used for private messages and attachment metadata; exact full schema and indexes need to be recovered from the authoritative application schema. |
| `account_security` | Created lazily by Worker helper | `user_id`, `session_version`, `updated_at`. |
| `notification_preferences` | Created lazily by Worker helper | `user_id`, `messages`, `groups`, `statuses`, `updated_at`. |
| `device_tokens` | Created lazily by Worker helper | `user_id`, `fcm_token`, `updated_at`. |
| `user_privacy` | Created lazily by Worker helper | `user_id`, `searchable`, `read_receipts`, `updated_at`. |
| `status_posts` | Created lazily by Worker helper | `id`, `user_id`, `content`, `created_at`, `expires_at`. |
| `chat_groups` | Created lazily by Worker helper | `id`, `name`, `description`, `owner_id`, `created_at`. |
| `group_members` | Created lazily by Worker helper | `group_id`, `user_id`, `joined_at`; composite primary key. |
| `group_messages` | Created lazily by Worker helper | `id`, `group_id`, `sender_id`, `body`, `created_at`. |
| `recovery_codes` | Migration `0001` | One row per user; salted digest, expiry, consumption timestamp. |
| `recovery_rate_limits` | Migration `0001` | Hashed identifier/account buckets and 15-minute attempt windows. |

## Blocking items before real D1 integration tests

1. Recover or authoritatively verify the original base schema for
   `users`, `friendships`, and `messages`, including column types,
   nullability, indexes, uniqueness rules, and foreign keys.
2. Confirm whether the lazy-created tables should remain runtime-created or
   move into versioned migrations. Avoid creating a second, conflicting
   definition.
3. Obtain a dedicated non-production D1 database and its own binding. The
   `database_id` currently in `wrangler.toml` is not to be used for testing.
4. Apply migrations only to that isolated database, then run real SQL
   integration tests for registration, login, recovery, direct messaging,
   group messaging, privacy, and media metadata authorization.

## Decision

Do not invent a new base migration from partial SQL usage. In particular,
do not add guessed constraints or indexes to the production schema. The
existing SQLite test validates the recovery migration's local SQL behavior
only; it is not a substitute for Cloudflare D1 integration testing.

## Additional historical-branch finding

The historical `feature/siraj-foundation-v1` branch contains two older
migrations, but they are not a safe substitute for the current schema:

- `0001_groups_media.sql` creates `groups`, while the current Worker
  creates and queries `chat_groups`.
- That historical migration creates `group_members` with a foreign key to
  `groups`; the current Worker-created `group_members` definition points to
  `chat_groups`. SQLite/D1 does not change an existing table's foreign-key
  target merely because a later `CREATE TABLE IF NOT EXISTS` is executed.
- The historical migration also creates `media_assets`, while the current
  Worker attachment flow uses message records plus Tigris object keys and
  does not use that historical media metadata schema.
- `0002_tigris_retention.sql` alters the historical `media_assets` table and
  must not be applied unless that exact earlier migration is installed and
  the current product still requires that schema.

Therefore, blindly restoring those old migration files could leave the
database with two group table names and incompatible foreign-key relationships.
Do not copy or apply them as current migrations.

## Worker-managed table definitions

The current Worker lazily creates these support tables with
`CREATE TABLE IF NOT EXISTS`: `account_security`,
`notification_preferences`, `device_tokens`, `user_privacy`,
`status_posts`, `chat_groups`, `group_members`, and
`group_messages`. Some definitions are repeated at multiple API paths.
These definitions should be consolidated only after checking the actual
non-production D1 schema, because existing tables are not altered by
`IF NOT EXISTS`.

## Next safe action

Obtain a read-only schema export (for example, `sqlite_master` table/index
definitions and `PRAGMA table_info` / `PRAGMA foreign_key_list`) from a
dedicated non-production D1 database or a verified database backup. Compare
it with the current Worker SQL before writing any migration. The available
repository integration does not expose Cloudflare D1 commands, so no D1
database has been created or queried in this task.

## Repository-history search (2026-11-19)

The Git history was checked beyond the current branch:

- The complete tree of `feature/siraj-foundation-v1` contains only
  `0001_groups_media.sql` and `0002_tigris_retention.sql`; neither defines
  `users`, `friendships`, or `messages`.
- The older `feature/recovery-code-password-reset` tree contains only
  recovery-code migrations; it does not contain the core schema.
- The `main` tree has no migrations directory and no schema export.
- The earliest available `src/src/index.js` revision was inspected; it does
  not contain `CREATE TABLE` definitions for the three core tables.
- The repository's Worker source therefore assumes these core tables already
  exist in the bound D1 database. Their authoritative definitions are not
  recoverable from the repository history inspected so far.

The CI run for audit documentation commit
`a7680525e85835b4125323f8381a6f2cba678018` completed successfully:
`44539078738`. This confirms the repository tests, SQLite recovery migration
test, and Worker syntax check pass; it does not validate the missing core
schema or a live D1 database.


## Live isolated D1 verification — 2026-11-20

A read-only schema inspection was added to the isolated test-D1 workflow and
completed successfully in run `44803949658` on commit
`9b32bb1eb12449cf5cd999b4a0fa5484385ca8d6`. The workflow first verified the
dedicated test configuration and applied only the already-versioned migrations
to `barq-phase2-test-2026-11-20` (database ID
`5bfada32-4f9b-4edb-85dd-3b3b30ab73b0)); it did not target production.

The read-only `sqlite_master` and `pragma_*` queries confirmed:

- The core tables `users`, `friendships`, and `messages` are absent from
  this isolated D1 database.
- The only non-system tables present are `d1_migrations`,
  `ephemeral_messages`, `recovery_codes`, `recovery_rate_limits`, and
  `revoked_sessions` (plus Cloudflare's internal `_cf_KV`).
- Consequently, there is no `users.phone` column or phone uniqueness index
  to inspect in this test database yet.

This confirms that the current isolated D1 is not ready for live account,
contact, friendship, messaging, or profile-photo integration tests. Do not
deploy the application Preview against this incomplete database and do not
invent a guessed base schema. Obtain the authoritative schema definition for
`users`, `friendships`, and `messages` from a verified backup or the
application owner, then review its constraints and indexes before creating a
versioned base migration for the isolated test database only.
