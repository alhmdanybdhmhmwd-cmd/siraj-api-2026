# BARQ Admin Phase 6 — Owner/Brain Handoff

Last updated: 2026-11-28  
Working PR: #11 — `barq-admin-foundation-2026-11-23`  
Last recorded code head when this handoff was prepared: `6fec4f629c0ff2857d4c9d997c72895b11b97579`

## Purpose

This file is an actionable handoff for the single BARQ Brain assistant inside BARQ Admin. It preserves unfinished work so an external access or device requirement does not stop independent development. BARQ Brain is also the guardian role; they are one assistant identity.

## Phase 6 work already present in the branch

- Owner-authenticated, read-only BARQ users API and Arabic RTL Users page, backed by existing BARQ accounts (no duplicate user database).
- Bounded search, pagination, masked phone numbers in lists, on-demand detail, and append-only audit events.
- Owner-authenticated, read-only groups API and Arabic RTL Groups page, with search, pagination, owner label and member count. It does not read private messages or media.
- UI tests for Users and Groups reachability and privacy expectations.
- A Worker regression test verifies both platform listing endpoints reject unauthenticated requests before querying BARQ data.
- Existing task queue leases, retries, dead-letter handling, checkpoint fencing and audit foundations remain in place.

These are source-level/CI features. They do not establish live Preview or real-device acceptance.

## Outstanding work — continue autonomously where possible

### A. Cloudflare build diagnosis

Latest observed Workers Builds check for head `6fec4f629c0ff2857d4c9d997c72895b11b97579`:

- Build ID: `5960951c-e83a-48f7-b98c-cfd09b76cd4f`
- Dashboard: https://dash.cloudflare.com/4c11a96ab2ad6915be273eb3c93102a7/workers/services/view/siraj-api/production/builds/5960951c-e83a-48f7-b98c-cfd09b76cd4f
- Observed check conclusion: failure; the GitHub check contains the dashboard link but not the build error output.

Saved Cloudflare integrations currently visible to SentinelX:
- `barq-admin-runtime`
- `barq-cloudflare-main`
- `barq-cloudflare-preview`

All three currently report: `Cloudflare: no zones visible to this token`.

Actions for BARQ Brain:
1. Obtain the actual build log from the Cloudflare dashboard for the exact Build ID above.
2. Identify the first causal error and the failing build stage; distinguish source compilation, configuration, dependency, account/permission and provider failures.
3. Compare the failing log with the exact Git commit and workflow configuration; do not infer a cause from the check status alone.
4. Record the diagnosis and a minimal isolated repair proposal.
5. If the saved integration still cannot see the required account/zone, guide the owner through reconnecting the integration in the protected integration UI. Never request that credentials or API tokens be pasted into chat.
6. Do not deploy, merge, change production settings, alter DNS, create paid resources, or apply migrations as part of diagnosis.

### B. Isolated Preview acceptance

When valid Preview credentials and isolated resources are available:
1. Verify the Preview Worker, D1 database and queues are separate from production.
2. Use synthetic test accounts/groups only.
3. Verify unauthenticated requests to users/groups return 401 and make no BARQ data query.
4. Verify authenticated user list/detail, masked list phones, search, pagination, audit records and owner scoping.
5. Verify group list/search/pagination/member counts and graceful `groups_unavailable` behavior.
6. Verify no private message or media content is read or returned.
7. Verify no Preview test writes to production resources.

If Preview access remains unavailable, keep developing offline tests and retain the exact pending checks for the later acceptance stage.

### C. Stage 5 knowledge acceptance carried into Stage 6

Complete and provide evidence for:
- Source indexing lifecycle across changed, renamed and deleted files, with revision-aware stale reports and no automatic destructive deletion.
- Exact path/revision citations and retrieval completeness/freshness reporting.
- Requirement vs implementation vs test evidence distinction and conflict detection.
- Prompt-injection resistance for indexed project content and images.
- BARQ / BARQ Admin project-scope isolation through every retrieval path, including full GitHub paths.
- Safe query handling and SQL LIKE/search edge cases.

### D. Automatic incident handling and repair

This remains a product requirement, not an operational feature until demonstrated end-to-end.

Build an isolated, synthetic incident demonstration:
1. Health/error signal enters monitoring.
2. A durable incident record captures service, time, evidence and correlation ID.
3. BARQ Brain diagnoses using logs and project knowledge.
4. A policy-bounded repair runs only in an isolated branch/Preview or performs a safe retry/recovery action.
5. Focused tests and regression checks run.
6. Recovery health checks confirm the affected behavior is restored.
7. A durable audit record and owner notification are produced.
8. Failed verification triggers safe rollback/stop and preserves evidence.

Protect user accounts, messages, media, sessions, database consistency, backups and audit history. Production deployments, migrations/data edits, destructive actions, secrets/permissions, paid resources and external communications require the owner's explicit approval. Never report a repair as successful without verification.

## Current verification checkpoint

For commit `6fec4f629c0ff2857d4c9d997c72895b11b97579`:
- Backend/auth tests: passed (run `46094811395`).
- Admin Quality: passed (run `46094807430`, job `140823679632`).
- Bundle diagnostic: passed (run `46094807399`, job `140823614518`).
- Admin Mobile Quality: still running at handoff time; Flutter setup and Dart analysis had started. Do not claim AppAuth or Kotlin success until the exact-head job completes.
- Cloudflare Workers Build: failed; see exact Build ID above. Root cause remains unknown until the real log is reviewed.

## Release and safety state

- PR #11 remains Draft/open and unmerged.
- No APK build/package is authorized by this handoff.
- No production deployment, migration, production data mutation, merge, DNS change or paid-resource creation is authorized.
- Keep this handoff current as checks finish. Always record the exact commit SHA and actual test evidence.


## Follow-up engineering notes — 2026-11-28

- The first mobile CI failure on `b82123e01bbd1326658915fff2b8d7227a713dd6` was diagnosed from job logs: Dart formatter required a multiline wrap in the new Groups description condition. This was corrected in `829521770082ae9ec9094d4252a0f045ab784580`. On that exact SHA, Flutter dependency resolution, formatter, and Dart analysis passed; the mobile job was subsequently cancelled during Flutter tests when a newer commit arrived, so full mobile CI remains unproven.
- Hardened `GET /v1/platform/users`: database/query/audit failures now return a stable `503 { error: "users_unavailable" }` instead of bubbling an unhandled Worker exception. A regression assertion was added in `admin/worker.test.mjs`.
- Added a Groups UI assertion that signed-out state does not display fabricated placeholder group records. This intentionally retriggers the mobile workflow; verify its result on the exact current PR head before counting it as passed.
- Last observed complete Admin Quality run before the users-unavailable hardening: success on `829521770082ae9ec9094d4252a0f045ab784580`. Backend tests also passed on that SHA. The subsequent `b8c8acf` and `7eef71c` changes require fresh exact-head checks.
- The mobile workflow cancellation is not a code failure; it is not a pass either. Do not infer Flutter tests, AppAuth wiring, or Kotlin compilation succeeded.


## Follow-up checkpoint — 2026-11-28, Phase 7 slice and owner handoff

### Phase 7 implementation slice
- Added owner-authenticated read-only `GET /v1/platform/overview` with aggregate user/group totals, an explicit group-table availability flag, collection timestamp, and audit event.
- Added Arabic RTL **إدارة المنصة** screen, owner-gated empty state, loading/error display, and manual refresh. No local caching or write actions.
- Added backend privacy/auth tests and a mobile owner-gate widget test.
- Exact implementation commit before the latest UI-only correction: `f21c258e2fe390ae2e28f18e0c3810f4d6b1335e`.
- Admin Quality passed on that commit: 91 tests, 0 failures. Backend tests and bundle diagnostic passed.
- The mobile workflow failed only the new overview widget test because the signed-out owner prompt was rendered twice (once inside the shared error state and once as a separate Text). Removed the redundant Text in commit `56ac5c98ce5fd5d619d8f36ea800faffb4acb32f`. This is a focused UI correction; rerun mobile CI on the new exact HEAD before claiming the fix passes.

### External blockers — hand off to owner + BARQ Brain; do not block offline development
1. **Vercel CI integration rate limit**
   - Observed status: `Deployment rate limited — retry in 24 hours`.
   - This is an external provider limit, not a source-code test failure. No deployment was attempted.
   - Owner/BARQ Brain action: after the cooldown, inspect the Vercel integration/project rate-limit and build logs; verify the correct project/team is connected and retry only a non-production Preview check. Do not promote or deploy production.
2. **Cloudflare account/zone visibility**
   - Previously recorded SentinelX integrations `barq-admin-runtime`, `barq-cloudflare-main`, and `barq-cloudflare-preview` did not expose the required account zones; one token was rejected for permissions.
   - The Cloudflare Workers Build check has repeatedly failed while GitHub exposes only a dashboard/build ID, not actionable provider logs.
   - Owner/BARQ Brain action: reconnect the correct Cloudflare account integration in the protected integration UI; grant the minimum read/build permissions needed for the intended Preview project; confirm the preview zone/account is visible; then inspect the exact build logs. Never paste API tokens or secrets into chat. Do not change DNS, production workers, production D1, or deploy production during diagnosis.
3. **Preview acceptance unavailable**
   - Isolated Preview verification remains pending until the provider integration and isolated resources can be inspected.
   - Owner/BARQ Brain action: establish separate Preview Worker + D1 + queue resources and synthetic fixtures, then run the acceptance list in section B above. Never point Preview tests at production.
4. **Physical Android device acceptance**
   - No APK was packaged and no real-device acceptance was performed in this slice.
   - Owner/BARQ Brain action at the agreed device-test stage: install only an explicitly approved test build on the target phone, verify sign-in/navigation/offline recovery/performance, and return logs without exposing secrets.

### Next engineering actions
- Recheck PR #11 head and run the targeted mobile workflow on the corrected overview screen.
- Add focused tests for the platform overview's successful aggregate rendering and API error state where the test harness can safely mock the authenticated API.
- Continue offline Phase 7 read-only diagnostics and Phase 5/6 acceptance work without waiting for provider access.
- Keep PR #11 draft/open. No APK, merge, deployment, migration, production data mutation, or destructive action is authorized.


## Latest continuation — 2026-11-28

- Diagnosed the failed mobile test on `f21c258`: the signed-out owner prompt was rendered twice. Removed the redundant second widget in `56ac5c9`. The fix has not yet been declared verified.
- Continued Phase 7 read-only platform work: overview now performs an Admin D1 `SELECT 1` probe and reports database probe state, AI binding configuration presence (not AI service reachability), and runtime mode. The mobile overview presents these indicators only after authenticated data is loaded.
- Added regression assertions that signed-out users do not see totals or unverified health indicators.
- Latest recorded source SHA before this handoff update: `2291b4dd40407a4ef78d4e0b92990ef51add4640`. A fresh BARQ Admin Quality run was queued for this SHA; exact-head CI results for the later health-indicator changes are still pending. The earlier run on `7078e111` passed Admin Quality, auth tests, and bundle diagnostics, but its mobile job was cancelled when the newer commit arrived.
- Vercel's external status remains `Deployment rate limited — retry in 24 hours`. This is recorded for the owner and BARQ Brain; continue code/tests offline.
- Cloudflare integration/account zone visibility and isolated Preview access remain recorded external blockers. BARQ Brain/owner should reconnect the correct least-privilege Cloudflare integration, inspect provider build logs, and establish separate Preview resources when available. No credentials should be pasted into chat.
- No APK was packaged, no merge/deploy occurred, and no production resource was changed.


## Exact-head verification update — 2026-11-28, commit 8bf614588765900d63ac4b96ac92eca032ec33ff

- Backend tests: **passed** — run `46096630671`.
- Admin Quality: **passed** — run `46096630702`, job `140829356566`; Worker syntax, Admin unit tests, isolated schema/audit immutability, BARQ D1 schema coexistence, workspace/task concurrency, read-only Preview preflight, and isolated Preview template checks all completed successfully.
- Admin Mobile Quality: formatter, Flutter analysis, and Flutter widget tests: **passed** on this exact SHA. Android SDK/NDK setup and Gradle setup also passed.
- Android AppAuth merged-manifest validation: **in progress** at the latest poll. Kotlin compilation has not started yet. Do not claim Android platform acceptance until both remaining steps finish successfully.
- The mobile widget test was updated to assert the actual signed-out privacy explanation and ensure aggregate totals/health indicators remain hidden before owner authentication.
- PR #11 remains Draft/open. No APK packaging, merge, deployment, production migration, production data mutation, or destructive action was performed.

## Phase status clarification

- Phase 5 acceptance remains open; knowledge indexing freshness/coverage, citations, conflict handling, injection resistance, and project isolation still require evidence.
- Phase 6 remains in progress; isolated Preview and end-to-end repair acceptance remain outstanding.
- The owner explicitly approved **preparatory/partial Phase 7 implementation in parallel** with Phases 5 and 6. This does not close either earlier phase and does not authorize declaring Phase 7 formally started/accepted ahead of those gates.
- BARQ consumer app remains in Phase 9 real-device testing.


## Latest continuation — overview request race protection (2026-11-28)

- Commit `2961e559e663cbaf81d712f8b08d6fa8718c2fcf` adds a request-generation guard to the platform overview loader. If refreshes overlap, only the newest request may update the displayed overview, error, or loading state.
- If the owner session is absent, the overview snapshot is cleared before showing the owner-login prompt. A stale in-flight request cannot repopulate the signed-out screen.
- This mirrors the existing stale-response protections on Users and Groups. The change is source-level only until exact-HEAD Flutter tests pass.
- The previous run on `1dff2bb42e107a17994cdeeec453dfb42e937840` completed Backend tests and Admin Quality successfully. Flutter formatter, analysis and widget tests passed; the mobile job was superseded during AppAuth manifest validation, and Kotlin compilation was skipped. Android validation remains open.
- Exact-head workflows for `2961e559e663cbaf81d712f8b08d6fa8718c2fcf` were not yet visible at the last poll. Do not claim tests passed for this new code until fresh exact-head evidence is available.
- PR #11 remains Draft/open and unmerged. No APK, merge, deployment, migration, production data access/change, or destructive action was performed.
