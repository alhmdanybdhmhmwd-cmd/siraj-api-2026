# BARQ Phase 2 — Application Foundation and API Security

Status: IN PROGRESS — source/CI foundation verified; isolated live integration remains open.  
Working branch: `barq/phase-2-android-ci-2026-11-20`  
Current baseline before this documentation update: `9211c3eb2e95e1dd37175d7d582ab53c24bcd119`

> This status supersedes older statements in this file that Android source was outside the repository or that Flutter CI had not yet run.

## Verified implementation

- Flutter Android source is checked into `android/`.
- Android package namespace/application ID: `com.barq.app`; Firebase Android config is present in the source tree.
- REST, media, and realtime origins are build-time selectable with `BARQ_API_BASE`, `BARQ_MEDIA_BASE`, and `BARQ_REALTIME_URL`. Production values remain defaults; preview values must be supplied explicitly for isolated testing.
- Flutter stores the bearer token with `flutter_secure_storage` and validates saved sessions through `GET /api/me` at startup.
- Worker validates JWT signature/expiry and session version; recovery rotates the session version.
- Worker has read-only liveness/readiness probes: `GET /health/live`, `GET /health/ready`; readiness uses `SELECT 1 AS ok`.
- Test Wrangler config points to D1 `barq-phase2-test-2026-11-20`, ID `5bfada32-4f9b-4edb-85dd-3b3b30ab73b0`, distinct from production ID `0db93afd-4bf5-4423-9e25-7a2f4f4bdbe0`.
- Worker source contains `POST /api/contacts/match`; a route-not-found error from an older deployed origin does not prove the current source lacks the route. Verify it against Preview before considering deployment.
- Worker source contains the current ephemeral-message, private-invite-code, transcription, and profile-photo routes. Presence in source is not equivalent to live Preview verification.
- Android logout unregisters the current installation's FCM token, calls `POST /api/logout` while the bearer token is still available, stops realtime/Nearby services, then clears local session and offline queues. Server revocation stores only a SHA-256 token hash and is scoped to that exact bearer token; it does not invalidate another device's token. If the network is unavailable, local logout still completes but server-side revocation is best-effort.

## CI verification on the current branch

Commit `9211c3eb2e95e1dd37175d7d582ab53c24bcd119`:
- Android quality gate run `44770127390`: success.
  - Dart analysis: success.
  - Flutter tests: success.
  - ARM64 debug diagnostic APK: built and uploaded.
  - Optimized ARM64 release test APK: built and uploaded.
- Backend tests run `44770144648`: success.
- Optimized ARM64 test APK artifact size: 16,545,026 bytes (about 15.77 MiB).
- Diagnostic APK artifact size: 82,173,796 bytes.
- The artifacts are CI test artifacts, not a signed production release.

A contract assertion now verifies that the three Android origin selectors remain available. Backend CI on commit `4f89d465b9b1aa9a4fa28b7a08144df0a8d41921` passed all 96 tests, including the new device-scoped logout test. Android quality gate on commit `ab6f35d60521e6333d90db3e0e607f36ad443bf9` has passed Dart analysis and Flutter tests; APK build/upload steps were still running at the time of this update.

## Still required to close Phase 2

1. Backend CI recheck completed on `4f89d465b9b1aa9a4fa28b7a08144df0a8d41921` (96/96 passing); Android quality gate APK build/upload still requires final run confirmation.
2. Establish or verify an isolated Preview Worker/API origin and configure its REST, media, and realtime endpoints; do not use production D1 for testing.
3. Run authenticated Android-to-Preview integration tests for registration/login, session restore, `/api/me`, contacts, messages, groups, media, and realtime.
4. Server-side bearer-token revocation is now implemented and unit-tested as device/token-scoped; confirm it on the isolated Preview and on two actual devices. Offline logout remains locally effective, while server revocation requires network access.
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
