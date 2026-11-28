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
