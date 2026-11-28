# BARQ Admin — Phase 7: BARQ platform management

Status: **preparation started; phase transition and acceptance are not declared**  
Working PR: #11 — `barq-admin-foundation-2026-11-23`

## Purpose

Give the owner a safe, unified operational view of the existing BARQ platform from BARQ Admin. BARQ remains the consumer product; SPARK remains its stories feature. BARQ Admin is a separate owner-only control surface, and BARQ Brain is its single assistant/guardian identity.

Phase 7 must manage the existing BARQ platform rather than create a parallel consumer platform, duplicate user database, or separate production runtime.

## Implemented preparation slice

### Platform overview — read-only

- Owner-authenticated `GET /admin/v1/platform/overview` (Admin handler path: `/v1/platform/overview`).
- Returns aggregate user and group totals only; no user identifiers, phone numbers, credentials, messages, media, or group content.
- Group count is explicitly marked unavailable when the existing group tables are not present; the endpoint does not create or migrate tables.
- Records the read in the append-only Admin audit trail.
- Arabic RTL mobile destination **إدارة المنصة**, with loading/error/owner-gated states and manual refresh.
- No local cache of platform totals and no write controls.

This is source-level implementation. Live Preview, physical-device, and production integration are not verified.

## Phase 7 work packages

1. **Platform overview:** aggregate service/account/group indicators, timestamps, availability state, and safe error reporting.
2. **Service health and diagnostics:** read-only health summaries, recent incident references, deployment/build status where an authorized integration exposes it, and correlation IDs. Never fabricate a healthy status when evidence is missing.
3. **Platform configuration inventory:** read-only view of effective configuration names and non-secret values only. Never display secret values, tokens, signing material, or private keys.
4. **Feature and capability registry:** document existing BARQ capabilities and their state before proposing changes. Any enable/disable operation requires a preview, explicit owner approval, audit entry, and rollback plan.
5. **Account and group operations:** preserve the existing Users/Groups pages. Do not add suspension, restoration, deletion, group removal, or membership changes until product rules, authorization, confirmation, recovery, and audit behavior are specified and tested.
6. **Operational activity:** searchable audit/incident views with strict pagination and privacy boundaries.
7. **Owner approvals:** route consequential actions through the existing approval workflow; an approval must identify the exact action, target, impact, environment, and expiry.

## Data and safety rules

- Reuse the existing BARQ Worker and D1 binding; keep Admin-owned records in the `admin_*` namespace.
- Read only the minimum data needed. Aggregate counts are preferred over individual records.
- Never expose passwords, password hashes/salts, access/refresh tokens, secrets, private messages, private media, or unnecessary personal data.
- Every privileged read or write must be owner-authenticated and audited. Do not cache sensitive platform data on the phone.
- No automatic destructive cleanup. Preserve account, message, media, group, audit, and historical records.
- No production migration, production data mutation, secret/permission change, paid-resource change, external communication, merge, or deployment without specific owner approval.
- Keep operational repair isolated until the repair workflow has passed end-to-end tests and explicit production runbooks are approved.

## Acceptance gates

- API tests prove authentication is checked before any BARQ data query.
- Aggregate response schema is bounded and contains no personal/private fields.
- Missing optional tables produce a documented unavailable state, not a false zero or an unhandled exception.
- Audit events are append-only and contain no sensitive payloads.
- Flutter widget tests cover owner-gated, loading, error, and successful aggregate states.
- Isolated Preview tests use synthetic data and verify no production resource is touched.
- Real-device usability is verified on the supported target device before release.
- Every mutating capability has a written policy, exact confirmation preview, audit evidence, recovery/rollback, and owner approval gate.

## Current boundaries

- Phase 7 preparation may proceed alongside the unfinished Phase 5/6 acceptance backlog as explicitly agreed by the owner.
- This does **not** mark Phase 5 or Phase 6 technically complete and does not authorize skipping their outstanding gates.
- No merge, APK packaging, live deployment, production migration, production data change, or destructive action is authorized by this scope document.
