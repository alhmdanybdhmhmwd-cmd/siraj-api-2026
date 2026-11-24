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


## Owner directive update — 2026-11-24

The owner has now explicitly asked BARQ Brain to carry forward the full project understanding accumulated with the prior assistant, and to let the owner resume work with a short instruction such as "واصل، اشتغل، ابنِ نفسك". The knowledge foundation must therefore include not only current code but also the owner-approved decisions, rejected/postponed ideas, roadmap, historical bugs and fixes, CI evidence, unresolved blockers, and working preferences recorded in `BARQ_OWNER_CONTEXT.md`.

A navigation source was added at `admin/knowledge/BARQ_BRAIN_MASTER_INDEX_AR.md`. The owner context was expanded with the current repository map and a continuation protocol. The Brain system prompt now points to these canonical documents and instructs it to recover the latest checkpoint, verify branch/commit/CI, avoid repeated work, cite evidence, and report missing knowledge coverage.

This is a source/documentation and prompt improvement only. It does NOT prove that the documents have been ingested into Admin D1 or that live Brain retrieval can access them. The indexer supports Markdown and should include these documents in a future complete, revision-pinned ingestion run.

The owner also directed continued preparation of a smaller Admin APK for the Galaxy S7. The current controlled build is ARM64-only; its final size and successful artifact upload must be confirmed from workflow evidence. Physical installation, Google sign-in, and live Admin API use remain untested on the S7.

The owner's desired "continue" experience is the product target. Durable server-side background execution, repository editing, test/build orchestration and autonomous resume must be reported as unavailable until each is implemented and tested end-to-end. Never imply that a prompt or knowledge document alone grants those capabilities.

## Verified implementation progress — 2026-11-25

- The guarded indexer now retries transient GitHub API reads as well as Admin knowledge API writes, with bounded retry/backoff behavior.
- Each ingestion result now includes a repository coverage report grouped by product domain and file extension, with explicit excluded-path reasons and oversized-file counts. The GitHub Actions summary publishes these breakdowns for each batch.
- Regression tests cover coverage classification and transient GitHub API retries.
- The latest observed Admin Quality run before these coverage changes passed its Admin Worker/unit/schema/workspace checks; mobile quality was still compiling Android Kotlin. The coverage change itself must pass its new CI run before it is treated as verified.
- Still not complete: live Preview ingestion and retrieval, multi-batch completion against the actual isolated D1 store, source freshness reconciliation for deleted/renamed files, and representative live answer/citation acceptance tests. Do not claim Phase 2 complete until these are evidenced.

## Freshness reconciliation implementation — 2026-11-25

- Added Admin-only migration `0008_knowledge_freshness.sql` with `last_seen_revision` and `is_stale`; historical rows are retained.
- Each successfully indexed chunk records the latest commit revision it was seen in and is reactivated as fresh.
- The indexer calls `POST /v1/knowledge/reconcile` only when the current immutable revision has no remaining eligible batches. The endpoint marks repository-prefixed rows not seen in that revision as stale; it does not delete historical evidence.
- Brain retrieval prefers fresh sources and explicitly labels stale evidence as historical/verification-required in the model context.
- Added tests for complete-revision validation, workspace-authenticated reconciliation, no-history-deletion behavior, and final-batch-only reconciliation. CI must pass before this is considered verified; live Preview migration/ingestion is still required.

## Current release gate — 2026-11-25

The indexer now produces source-domain/file-type coverage and performs bounded retries. Non-destructive freshness reconciliation is implemented: a completed immutable-revision ingestion marks absent prior repository sources stale, while preserving historical rows; fresh knowledge is ranked ahead of stale evidence, which is explicitly labelled. Automated tests cover the new behavior.

This does not complete Phase 2. Latest CI for the newest changes must pass; dedicated Preview configuration is missing; the repository has not yet been ingested into Admin Preview D1; and live retrieval/citation acceptance remains untested. Exact missing Preview deployment values and ingestion secrets are recorded in `BARQ_BRAIN_CURRENT_CHECKPOINT.md`.
