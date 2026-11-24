# BARQ Admin Phase 2 — Knowledge and Project Understanding

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
- Dedicated Admin Preview D1/Queue/AI bindings are not yet configured and verified. Therefore live indexing into the Admin knowledge store, live AI retrieval, and complete coverage are still blocked.
- No physical Android acceptance test or live Google OIDC test is claimed.

## Phase 2 work sequence

1. Preserve and validate the owner decision seed; identify conflicting or time-sensitive statements.
2. Validate indexer safety, exact allowlist enforcement, chunk identity, retry behavior, batch completeness, and source revision tracking.
3. Index the approved repository into the dedicated Admin Preview knowledge store once that isolated environment is available.
4. Produce a coverage report by source domain and file type, with skipped reasons and unresolved sources.
5. Add incremental refresh and stale/renamed/deleted-source reconciliation.
6. Test retrieval relevance, cross-project separation, contradictory decisions, stale evidence, and prompt-injection resistance.
7. Demonstrate answers for product architecture, roadmap, feature requirements, known issues, and next authorized task with exact citations.
8. Do not claim Phase 2 complete until all acceptance evidence below is present.

## Acceptance evidence

- Exact repository/ref/commit and ingestion run records.
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
