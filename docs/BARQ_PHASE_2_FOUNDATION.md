# BARQ Phase 2 — Application Foundation and API Security

Status: IN PROGRESS — source/CI foundation verified; isolated live integration remains open.  
Working branch: `barq/phase-2-android-ci-2026-11-20`  
Latest verified source commit before this documentation update: `ffbff4dac3e9a4ec7dddb98dfd3dbbe6dac82dba`

> This status supersedes older statements in this file that Android source was outside the repository or that Flutter CI had not yet run.

## Verified implementation

- Flutter Android source is checked into `android/`.
- Android package namespace/application ID: `com.barq.app`; Firebase Android config is present in the source tree.
- REST, media, and realtime origins are build-time selectable with `BARQ_API_BASE`, `BARQ_MEDIA_BASE`, and `BARQ_REALTIME_URL`. Production values remain defaults; preview values must be supplied explicitly for isolated testing.
- Flutter stores the bearer token with `flutter_secure_storage` and validates saved sessions through `GET /api/me` at startup.
- Worker validates JWT signature/expiry and session version; recovery rotates the session version.
- Worker has read-only liveness/readiness probes: `GET /health/live`, `GET /health/ready`; readiness uses `SELECT 1 AS ok`.
- Test Wrangler config points to the verified isolated D1 `barq-phase2-test-2026-11-20`, ID `5bfada32-4f9b-4edb-85dd-3b3b30ab73b0`, distinct from production ID `0db93afd-4bf5-4423-9e25-7a2f4f4bdbe0`. Provisioning workflow re-verified this existing database without creating a duplicate.
- Worker source contains `POST /api/contacts/match`; a route-not-found error from an older deployed origin does not prove the current source lacks the route. Verify it against Preview before considering deployment.
- Worker source contains the current ephemeral-message, private-invite-code, transcription, and profile-photo routes. Presence in source is not equivalent to live Preview verification.
- Android logout unregisters the current installation's FCM token, calls `POST /api/logout` while the bearer token is still available, stops realtime/Nearby services, then clears local session and offline queues. Server revocation stores only a SHA-256 token hash in the versioned D1 migration `migrations/0002_revoked_sessions.sql`, records the token expiry, and is scoped to that exact bearer token; it does not invalidate another device's token. If the network is unavailable, local logout still completes but server-side revocation is best-effort.

## CI verification on the current branch

- Android quality gate run `44779226464`: fully successful — dependency install, Dart analysis, Flutter tests, ARM64 debug build/upload, optimized ARM64 release test build/upload.
- ARM64 release test APK artifact: **16,545,069 bytes** (about 15.77 MiB); debug diagnostic artifact: **82,173,540 bytes**. These are CI test artifacts, not a signed production release.
- Latest Backend CI run `44781774768` on commit `ffbff4dac3e9a4ec7dddb98dfd3dbbe6dac82dba`: **98/98 Node tests passed**, **4/4 SQLite migration tests passed**, D1 schema inspection passed, test-vs-production target guard passed, Worker syntax check passed, and Android Firebase/signing-safety check passed.
- The Android Firebase config package, Gradle namespace, and application ID all match `com.barq.app`. No JKS/keystore/P12/PFX signing file is tracked in the repository. Current Gradle release build uses the debug signing config for test builds; a final production signing key must remain user-controlled and must not be committed.
- Isolated D1 provisioning verification run `44781345825`: passed; it recognized the existing test database, skipped duplicate creation, and verified the database ID differs from production.
- Remote test-only migration run `44781701391`: passed; Wrangler applied `0002_revoked_sessions.sql` to D1 `5bfada32-4f9b-4edb-85dd-3b3b30ab73b0`. The production database was not targeted.
- Local Worker HTTP health probe run `44781710942`: passed for both `/health/live` and `/health/ready`, using local isolated D1 state.
- Scheduled cleanup now deletes expired revoked-session token hashes; a unit test verifies the expiry cutoff and the cron schedule remains every 15 minutes in both production and isolated test Wrangler configs.

## Still required to close Phase 2

1. Backend CI recheck completed on `1aee039df3300ad928046df49db41c329640027e` (97/97 Node tests plus 4/4 SQLite migration tests passing). Android quality gate run `44779226464` passed Dart analysis, Flutter tests, ARM64 debug APK build, and debug artifact upload (82,173,540 bytes). The optimized split-per-ABI ARM64 release test APK build/upload was still running at this update.
2. Establish or verify an isolated Preview Worker/API origin and configure its REST, media, and realtime endpoints; do not use production D1 for testing.
3. Run authenticated Android-to-Preview integration tests for registration/login, session restore, `/api/me`, contacts, messages, groups, media, and realtime.
4. Server-side bearer-token revocation is implemented through migration `0002_revoked_sessions.sql` and unit-tested as device/token-scoped; apply the migration only to isolated Preview, then confirm it on two actual devices. Offline logout remains locally effective, while server revocation requires network access.
5. Confirm no production secrets or signing credentials are committed; configure release signing only in a user-controlled secure environment.
6. Record Preview test evidence and close any contract mismatch before marking Phase 2 complete.

## Safety boundaries

- No production Worker deployment, production D1 migration/write, or production data test.
- No PR merge or promotion without explicit user approval.
- Never request signing credentials or Cloudflare secrets in chat.
- No final APK release before all agreed features and phases are complete.
- Do not repeat work already verified; investigate only new failures or uncovered gaps.

## Related phase ledger

See `docs/BARQ_12_PHASE_MASTER_PLAN_AR.md` for the authoritative 12-phase scope and completion status. Phase 1 (audit/inventory) is complete and must not be repeated. Phase 2 remains in progress.
