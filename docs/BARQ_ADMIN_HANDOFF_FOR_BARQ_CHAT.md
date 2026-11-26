# BARQ Admin handoff for the BARQ consumer-app workstream

**Purpose:** This note is the integration and ownership boundary between the independent BARQ Admin project and the original BARQ consumer app. It is written so a separate development conversation can understand what is ready, what is missing, and what must not be mixed.

**Last reviewed Admin workstream:** `db86c91f87bc1135fd75e7fa8a591e207a66e3cf` (latest verified CI and Preview-status record)  
**Latest roadmap update:** `6984fadc16285aa88c5aa2e94b7f5c0886396c69`  
**Admin branch:** `barq-admin-foundation-2026-11-23`  
**Admin PR:** [#11](https://github.com/alhmdanybdhmhmwd-cmd/siraj-api-2026/pull/11)  
**Consumer-app branch (separate workstream):** `barq/ux-media-chat-spark-2026-11-23`

## 1. Non-negotiable project boundary

- **BARQ** is the original consumer application.
- **SPARK / سبارك** is the stories feature inside BARQ only.
- **BARQ Admin** is a separate owner/admin Android application and service boundary.
- **BARQ Brain** is the assistant planned inside BARQ Admin. It is not SPARK and is not the consumer-app assistant unless a future, explicitly approved product decision says otherwise.
- Keep work on the Admin branch and consumer-app branch separate. Do not copy Admin files into the consumer app, do not modify consumer-app files from the Admin workstream, and do not merge branches as a shortcut.
- No production deploy, production database migration, real-user moderation action, public publishing, paid campaign, or external outreach without the owner's explicit approval.
- The current PR is still open and draft. Its base currently points to the consumer-app branch; do not merge it. Treat that as a repository workflow risk to resolve deliberately, not permission to combine the projects.

## 2. What BARQ Admin currently provides (verified in code)

- Separate Admin Worker API and D1 migration schemas for workspace, tasks, checkpoints, approvals, audit events, and indexed project knowledge.
- Owner-scoped HS256 bearer-token verification. Expected issuer is `barq-admin-auth`, audience is `barq-admin`, and owner subject is pinned in server configuration.
- Task creation/listing with idempotency support; checkpoint writes use optimistic version checks.
- Task status transition validation and compare-and-set protection against stale status updates.
- Client requests cannot set `running` or `completed`; those statuses are reserved for the server worker.
- Approval records for sensitive action previews; append-only audit immutability is enforced by database triggers.
- A Queue consumer skeleton that claims queued tasks with a 10-minute lease and asks Workers AI to generate a draft response based on indexed project knowledge.
- Initial GitHub repository indexing utility with path/content safeguards and HTTPS-only Admin API URL validation.
- Initial Flutter RTL client shell with cached workspace/tasks/approvals and an offline outbox for task drafts.

## 3. Latest quality evidence

At commit `0cff8cfa885c45faf5dfd7605571e8450c9a4c4e`, GitHub Actions reported success for:
- BARQ Admin server syntax, unit tests, isolated Admin schema, append-only audit triggers, coexistence checks with the BARQ D1 schema, task idempotency, and checkpoint concurrency.
- BARQ Admin Flutter dependency resolution, formatting, `flutter analyze` (no issues), Flutter tests, Android SDK/NDK setup, AppAuth wiring, and Android debug Kotlin compilation (`BUILD SUCCESSFUL`). The workflow did not package an APK.
- Backend authentication tests, D1 migration SQL checks, and consumer-backend compatibility checks.

The documentation-only follow-up commits `ba920f7` and `db86c91` record those results and correct the Vercel status history. Backend tests also passed on `db86c91`; the latest Admin Quality run for that documentation-only revision was queued when this handoff was updated. A separate Wrangler `deploy --dry-run` diagnostic passed on `ba920f7`, producing a 381.84 KiB bundle (71.20 KiB gzip) and resolving the configured bindings.

Vercel reported a Ready Preview deployment for the tested `0cff8cfa` revision at [the Admin branch Preview](https://siraj-api-2026-git-barq-admin-foundation-2026-11-23-siraj-01fc.vercel.app). This does not verify the Cloudflare Worker or live Admin runtime. Cloudflare Workers Builds separately failed for build `c0e84cad-6580-46e3-9b08-16269e3ca4e1`; the available GitHub check exposes no actionable failure log, so its root cause remains unknown.

These results prove only the named CI and Preview evidence for the named revisions. They do **not** prove live Google sign-in, production D1 migration, live indexing/retrieval, Queue delivery, or physical-device acceptance.

## 4. Critical missing pieces / known risks

### Identity and device security
1. Google OIDC Authorization Code + PKCE, Worker-side RS256/claims/nonce verification, owner allowlisting, short-lived Admin JWTs, and rotating opaque refresh tokens are implemented in code.
2. Server-backed device/session records, refresh-token hash history and replay revocation, logout, device listing, per-device revocation, and revoke-all routes are implemented in code.
3. Auth rate limiting and append-only security audit events are implemented; signing-key rotation procedures, concurrency-focused refresh tests, full threat review, and live integration validation remain outstanding.
4. The mobile client includes AppAuth, secure token storage, refresh handling, logout, and a device-management dialog. Real Google credentials, dedicated Preview bindings, and physical-device callback/revocation tests have not yet been supplied or verified.
5. Never put the JWT signing secret, provider credentials, GitHub tokens, or other server secrets in the APK.

### Worker reliability and long-running execution
1. Queue/D1/Workers AI bindings are not configured and verified in a dedicated Admin Preview environment.
2. The worker uses a 10-minute lease and attempts renewal every 4 minutes while the AI call is active. Lease-renewal helpers and ownership-loss tests exist. This is source/CI evidence only: real Queue execution, timer behavior under Cloudflare Worker lifecycle limits, worker termination, duplicate model work/cost, and recovery still require Preview integration tests.
3. Recovery after worker termination, retry policy under real queue delivery, dead-letter queue configuration, poison-message handling, operational alerts, and worker health monitoring are not end-to-end verified.
4. Current BARQ Brain behavior is **server-side draft generation and checkpointing only**. It does not autonomously edit GitHub repositories, run arbitrary commands, deploy, or operate the consumer app.
5. A task created offline on the phone remains a local draft until the phone reconnects and submits it. Only after server acceptance/queueing can server-side work continue with the phone offline.

### Mobile app and sync
1. There is no release-ready APK/AAB or verified signing/release pipeline. CI has compiled Android debug Kotlin sources but intentionally has not packaged an APK.
2. Real Google owner login, secure refresh flow, device management, and session expiry UX are implemented in source and pass unit/build checks where covered, but remain unverified against configured Preview credentials and on a physical device.
3. Cache/outbox are initial implementations. Test retry behavior, duplicate prevention, expired credentials, app termination, corrupt cache, conflicting versions, and multi-device updates before relying on them.
4. No proven end-to-end test has yet created a task on phone A and resumed/inspected it on phone B.
5. Push notifications, background status refresh, accessibility, localization polish, and device-size testing remain.

### Knowledge and engineering tools
1. Repository indexing has not yet been run against a configured Admin Preview API. Verify permissions, source revision, path exclusions, secret scanning, chunk limits, deletion/update semantics, and freshness.
2. Knowledge retrieval is currently a lightweight lexical ranker, not a mature semantic/hybrid retrieval system.
3. BARQ Brain needs grounded source citations, stale-source detection, prompt-injection isolation, task planning, tool permission scopes, approval gates, and explicit distinction between verified facts and assumptions.
4. GitHub read/write tools, Actions logs/artifacts, Preview environment operations, APK build automation, and controlled PR creation are not yet integrated end-to-end.

### Platform administration and launch
- User/group analytics, support/report handling, moderation tools, admin access logging for sensitive reads, and role-based delegated staff access are not complete.
- Growth/launch workspace, campaign review, analytics, alerts, scheduled reports, backup/restore drills, penetration testing, and production readiness are not complete.

## 5. BARQ consumer-app integration contract

The consumer-app workstream should continue to fix BARQ's own user-facing bugs independently. It does not need to wait for BARQ Admin to be complete.

When the owner later asks to connect the two products, first agree on a narrow, versioned integration contract. Until then:
- Keep consumer API and Admin API separate.
- Do not reuse Admin owner JWTs as consumer user sessions.
- Do not grant BARQ Admin direct access to consumer production D1 or private user content.
- If Admin eventually needs consumer operational metrics or support actions, expose a purpose-built, least-privilege server API with audit events and approval requirements; never let the Admin mobile app query production tables directly.
- Treat SPARK stories as a BARQ consumer feature, not an Admin feature.
- The consumer-app developer should report exact reproducible issues (device/OS, screen, steps, expected vs actual, logs/request IDs) and test fixes on the consumer branch only.

## 6. Recommended Admin completion order

1. Fix repository governance: choose a clean long-term Admin repository/base branch or otherwise document the intended PR base. Do not merge PR #11 into the consumer branch.
2. Implement trusted owner authentication and server-side device sessions, refresh/rotation, and revocation.
3. Provision isolated Admin Preview D1, Queue, AI, secrets, and worker bindings; run migrations only against the dedicated Admin Preview database.
4. Implement lease heartbeat/renewal, atomic checkpoint progression, idempotent side-effect records, bounded retries, dead-letter handling, and recovery tests.
5. Finish cross-device sync and conflict handling; test phone A to phone B and offline/online transitions.
6. Run repository indexing in Preview and verify freshness, exclusions, provenance, and retrieval citations.
7. Expand BARQ Brain's permissioned GitHub/CI tools with owner approvals for every sensitive action.
8. Build and verify a signed internal APK, then conduct security, backup/restore, and operational acceptance tests.
9. Only after these gates, consider production readiness; obtain separate owner approval before any production change.

## 7. Fast triage checklist for the consumer-app workstream

For every issue reported by the owner:
- Confirm the affected product is BARQ consumer app (not BARQ Admin and not the SPARK feature unless explicitly identified).
- Reproduce on the current consumer branch and record the exact commit.
- Inspect only the relevant consumer-app files and API contract.
- Add a regression test before or alongside the fix.
- Run the narrow test, then the relevant full suite.
- Report the cause, files changed, test evidence, and any unresolved risk.
- Do not alter Admin migrations, Admin Worker, Admin Flutter app, or Admin branch to fix a consumer-app issue.

## 8. Owner-facing status language

Use precise status labels:
- **Implemented in code**: code exists; runtime may still be unconfigured.
- **CI verified**: the named workflow passed for the named commit.
- **Preview verified**: exercised against isolated, real Preview resources.
- **End-to-end verified**: complete user flow tested, including failure/recovery.
- **Production approved**: only after explicit owner approval.

Do not describe BARQ Admin or BARQ Brain as complete, autonomous, multi-device-ready, or production-ready until the corresponding acceptance tests have passed.
