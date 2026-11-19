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
