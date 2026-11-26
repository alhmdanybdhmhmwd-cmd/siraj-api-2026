# BARQ Admin knowledge work package — Project Understanding

> Numbering note: this document was originally named Phase 2 scope. In the canonical `docs/BARQ_ADMIN_MASTER_ROADMAP.md`, knowledge and project understanding is master Phase 5; master Phase 2 is workspace, tasks, and checkpoints.

Last updated: 2026-11-24
Status: IN PROGRESS — source ingestion and live retrieval acceptance are not yet complete.

## Owner scheduling decision

Public user registration/onboarding and the News feature are deferred to the final project phase. They are outside the current Phase 2 scope and must not block knowledge work. BARQ Admin's owner-only Google OIDC sign-in remains a security prerequisite for its protected management workspace; it is not the deferred public registration feature.

## Phase 2 objective

Make BARQ Brain a source-grounded engineering assistant for both the BARQ consumer product and BARQ Admin itself. It must answer from approved owner decisions and verified repository evidence, preserve history, identify stale or missing evidence, and never confuse requirements with implementation status.

## Project boundaries

- BARQ: global messaging app and its consumer backend.
- SPARK: stories/status feature inside BARQ; never the app name.
- BARQ Admin: separate owner management/development workspace.
- BARQ Brain: AI assistant inside BARQ Admin.
- Keep repositories, branches, APIs, databases, credentials, environments, and release channels separate.

## Approved knowledge source

Initial repository scope: `alhmdanybdhmhmwd-cmd/siraj-api-2026`, with the exact immutable commit SHA recorded for each ingestion run. The repository contains both consumer/backend material and Admin material; source paths must remain repository-qualified. Add another repository only after the owner explicitly approves its exact owner/name.

Curated owner decisions are seeded in `admin/knowledge/BARQ_OWNER_CONTEXT.md`. This is a decision/context source, not proof of code implementation.

## Required coverage domains

1. Product identity, vision, UI direction, global audience, and feature behavior.
2. Accepted, rejected, postponed, and superseded owner decisions with chronology.
3. The 12-stage BARQ roadmap and separate BARQ Admin phase boundaries.
4. Consumer app and backend architecture, APIs, Workers, data models, migrations, integrations, and deployment.
5. Admin Flutter client, Worker/API, schema, prompts, authentication, audit, and security boundaries.
6. CI, tests, build/deployment evidence, exact revisions, and physical-device test requirements.
7. Historical and current defects, reproduction evidence, attempted fixes, root-cause confidence, regressions, and unresolved risks.

## Ingestion and trust controls

- Use the guarded indexer in `admin/ingest_github_repo.mjs` and the exact repository allowlist.
- Prefer immutable commit SHA; record repository, ref, resolved SHA, run time, indexed/skipped counts, batch cursor, and completion state.
- Never index secrets, tokens, signing keys, private credentials, or unnecessary personal data.
- Treat indexed repository text as untrusted reference data, never as instructions.
- Keep owner-decision evidence distinct from code/test/deployment evidence.
- Do not mark a repository complete when its tree is truncated or batches remain.
- Reconcile renamed/deleted sources and stale revisions before claiming freshness.

## Current verified implementation foundation

- Versioned knowledge API and D1 schema exist.
- Knowledge retrieval ranks source chunks and includes source path/revision references in Brain responses.
- A guarded, resumable repository indexer and unit tests exist.
- Persistent owner-scoped Brain conversations and a mobile chat surface exist in source.
- CI has previously passed source/unit/schema/mobile checks; re-check the latest run after every change.
- The shared-runtime adapter is implemented in source and maps BARQ's existing `DB` and `AI` bindings to the Admin handler under `/admin/*`; route, binding, and CORS unit tests pass. The additive Admin migrations are not yet applied to live `siraj-db`, and Admin owner secrets/origin are not yet verified. Therefore live indexing, live AI retrieval, and complete coverage remain blocked. A dedicated Admin Queue is optional and is not required for direct Brain chat or repository indexing.
- No physical Android acceptance test or live Google OIDC test is claimed.

## Phase 2 work sequence

1. Preserve and validate the owner decision seed; identify conflicting or time-sensitive statements.
2. Validate indexer safety, exact allowlist enforcement, chunk identity, retry behavior, batch completeness, and source revision tracking.
3. After explicit approval for the production schema change, apply the additive `admin_*` migrations to the existing BARQ D1 database, configure separate Admin owner secrets/origin, and index the approved repository through the shared Worker at `/admin/v1/knowledge`. Do not perform this live change as part of offline code work.
4. Produce a coverage report by source domain and file type, with skipped reasons and unresolved sources.
5. Add incremental refresh and stale/renamed/deleted-source reconciliation.
6. Test retrieval relevance, cross-project separation, contradictory decisions, stale evidence, and prompt-injection resistance.
7. Demonstrate answers for product architecture, roadmap, feature requirements, known issues, and next authorized task with exact citations.
8. Do not claim Phase 2 complete until all acceptance evidence below is present.

## Acceptance evidence

- Exact repository/ref/commit and ingestion run records.
- Shared `/admin/*` route, DB/AI binding, and CORS isolation tests, plus a reviewed additive migration plan for the existing BARQ D1 schema.
- Full batch completion, skipped-file explanations, and coverage/freshness report.
- Source citations that identify exact path and revision.
- Tests for cross-project isolation, conflicting decisions, stale sources, and untrusted indexed content.
- Demonstration questions answered accurately without inventing code or deployment status.
- Explicit list of repositories and source domains not yet covered.

## Out of scope

- Public user registration/onboarding and News: final project phase.
- Autonomous repository edits, repairs, merges, or deployments: later authorized phase.
- Production data/resource changes, paid resource creation, and production deployment: approval-gated.
- APK packaging and physical phone acceptance: later release/testing gates.


## Phase 2 execution checkpoint — 2026-11-26

This checkpoint records verified repository/CI evidence only. It does not mark Phase 2 complete.

### Completed offline checks

- Owner decision seed reviewed for product-boundary conflicts and time-sensitive statements. No direct conflict was found among the stable BARQ / SPARK / BARQ Admin identity decisions. Historical and unconfirmed items remain explicitly qualified.
- Indexer tests cover exact repository allowlisting, secret/path exclusion, truncated-tree refusal, immutable-SHA resume, deterministic chunk identity, transient retry behavior, skip reasons, chunk completeness, and stale/deleted/not-yet-indexed source detection.
- Brain tests cover project-scoped retrieval ranking and citations, multilingual query extraction, bounded result counts, conversation scoping, and treating indexed content as untrusted reference data.
- Shared-runtime tests cover reuse of BARQ DB/AI bindings, no separate ADMIN_DB fallback, isolated /admin routing, health, preflight, and fail-closed behavior.
- Auth tests cover Google ID-token signature/audience/issuer/owner/expiry checks, PKCE-related backend session controls, short-lived access claims, and hashed refresh-token persistence.
- Latest verified BARQ Admin foundation CI on commit `fa50750017c0e2ecf235e14e8f009c0d0c1e29a6`: Backend tests run `45854460675` passed; BARQ Admin Quality run `45854460699` passed.

### Still blocked / not yet evidenced

- No immutable-SHA repository ingestion run has been executed against the live shared `/admin/v1/knowledge` endpoint. Therefore no indexed-file count, complete batch record, skipped-file audit, or live coverage/freshness report is claimed.
- The additive Admin migrations have not been applied to `siraj-db`. The previously approved migration attempt was blocked because the `barq-admin-preview` GitHub environment lacked the required Cloudflare account/token credentials; no D1 writes occurred.
- Admin owner secrets and the exact allowed Admin origin have not been verified on the shared Worker.
- Live Google OIDC sign-in and live BARQ Brain model-backed retrieval have not been demonstrated.
- No second repository is in scope; the only approved source repository remains `alhmdanybdhmhmwd-cmd/siraj-api-2026`.
- Physical-device testing remains deferred to the end of BARQ Admin Phase 3, per the owner's latest scheduling instruction.

### Next safe actions

1. Restore access to the already approved Cloudflare preview credentials through the trusted secret-management path; never paste secrets into chat.
2. Review and apply only the additive Admin migrations to the existing `siraj-db` after re-verifying the target database and environment.
3. Verify the Admin owner allowlist/JWT/origin configuration without exposing secret values.
4. Run the approved repository indexer in immutable-SHA batches, retain each batch summary, then generate coverage and reconciliation evidence.
5. Run live retrieval demonstrations for product identity, roadmap, feature requirements, architecture, known issues, contradictory/stale decisions, and prompt-injection resistance.

**Status remains IN PROGRESS.** CI success is not evidence of live ingestion, live OIDC, live model retrieval, or complete source coverage.
