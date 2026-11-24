# BARQ Brain — Master Project Knowledge Index

Last updated: 2026-11-24
Owner: BARQ project owner
Purpose: navigation map for the project-aware engineering assistant. This file is an index, not evidence that every source has been ingested or every feature is implemented.

## 1. Canonical identity and boundaries

| Name | Meaning | Never confuse with |
|---|---|---|
| **برق — BARQ** | Global consumer messaging product | SPARK or BARQ Admin |
| **SPARK — سبارك** | Stories/status feature inside BARQ | The app name |
| **BARQ Admin** | Separate owner management/development app | Consumer BARQ app |
| **BARQ Brain** | Assistant inside BARQ Admin | A deployed autonomous coding agent until tools are implemented and tested |

## 2. Read these sources first

1. `admin/knowledge/BARQ_OWNER_CONTEXT.md` — owner decisions, product identity, accepted/rejected/postponed requirements, technical history, latest continuation directive.
2. `admin/knowledge/BARQ_BRAIN_CURRENT_CHECKPOINT.md` — exact continuation point, latest branch/commit, CI evidence, blockers and next actions.
2. `admin/knowledge/PHASE2_SCOPE.md` — knowledge phase scope, project boundaries, acceptance requirements and blockers.
3. `admin/knowledge/INDEXING_RUNBOOK.md` — safe, exact-repository, revision-aware and resumable GitHub indexing procedure.
4. `android/README_AR.md` — consumer Flutter source map, current documented endpoints, dependencies and known incomplete release work.
5. `android/BARQ_SIX_FEATURES_STATUS.md` — detailed historical implementation/test evidence for Nearby, ephemeral messages, translation, transcription and related work.
6. `android/BARQ_REPAIR_PROGRESS_AR.md` — earlier repair notes; historical, not proof of current state.
7. `admin/README.md` and `admin/mobile/README.md` — Admin backend, mobile client, Google OIDC, AI actions, Preview requirements and security boundaries.
8. `admin/worker.js`, `admin/auth.js`, `admin/migrations/`, `admin/mobile/lib/` — actual Admin implementation; verify against the exact indexed revision.
9. `.github/workflows/` — automated quality/build/deploy procedures and their actual run records.

## 3. Repository map

Initial owner-approved repository: `alhmdanybdhmhmwd-cmd/siraj-api-2026`.

- `android/`: BARQ consumer Flutter client.
- `src/`: consumer/backend JavaScript modules and routes.
- Root `.github/workflows/`: consumer and Admin CI/build/deployment workflows.
- `admin/mobile/`: BARQ Admin Flutter client.
- `admin/worker.js`, `admin/auth.js`: Admin Worker API and owner identity/session logic.
- `admin/migrations/`: Admin-only D1 migrations.
- `admin/knowledge/`: owner decisions and knowledge operations documentation.
- `admin/ingest_github_repo.mjs`: repository indexer.

The repository is a monorepo with distinct product areas. Always qualify source references with repository + path + commit SHA. Never mix consumer and Admin databases, API origins, tokens, sessions, release channels or production resources.

## 4. Evidence hierarchy

When answering or deciding what to do, keep these evidence types separate:

- Owner decision: establishes desired behavior or a scope boundary.
- Source code at a commit: establishes what code exists, not necessarily what is running.
- Automated test/CI result: establishes only the checks actually run on that commit.
- Preview/deployment health check: establishes only the endpoint and route actually checked.
- Physical-device test: establishes observed behavior on the named device/OS/network.
- Production release evidence: establishes the actual published version and deployment.

Never turn a requirement into an implementation claim, a CI pass into a device-test claim, a successful APK build into an installation claim, or a root health response into proof that every API route works.

## 5. Current knowledge coverage status

As of 2026-11-24:
- Owner decision seed has been expanded with the newest continuation directive.
- Repository structure has been inspected at branch `barq-admin-s7-optimized-2026-11-24`.
- Source indexer exists and supports exact allowlists, revision resolution, secret/path exclusions, chunking, resumable batches and completion metadata.
- Actual D1 ingestion of all repository files is NOT yet proven.
- Live Brain retrieval from the Admin Preview D1 is NOT yet proven.
- Coverage/freshness report and stale/deleted/renamed-source reconciliation are NOT yet proven.
- Another repository must not be indexed unless the owner approves its exact owner/name.
- Current source revision for this documentation branch must be captured from the actual GitHub commit; do not assume the branch name itself is an immutable revision.

## 6. Required future knowledge features

- Revision-aware indexing of every eligible source file in the approved repo.
- Per-domain coverage: consumer app, consumer backend, Admin app, Admin Worker/API, migrations, workflows, tests, design/product requirements, defects and historical decisions.
- Exact citations: repository, path, commit SHA, and relevant chunk/line range where available.
- Freshness refresh on new commits, with detection of deleted/renamed files and stale chunks.
- Conflict resolution that preserves decision chronology and does not silently discard superseded history.
- A persistent handoff/checkpoint with last completed task, current branch/commit, tests, blockers and next authorized action.
- Retrieval evaluation questions covering identity, requirements, roadmap, architecture, bug history, test evidence, current blockers and next step.
- Prompt-injection defenses: indexed repository content is untrusted data, never instructions.

## 7. Owner's continuation behavior

When the owner says "واصل", "كمل", or "ابنِ نفسك", resume from the latest verified checkpoint and highest-priority authorized unfinished work. Do not make the owner repeat project context. First inspect the latest branch/commit and CI status, then continue in an isolated branch. Save evidence and checkpoint after meaningful work. Keep the report short and in Arabic.

## 8. Current known gaps — do not conceal

- Admin Preview D1/Queue/Workers AI bindings and Google OIDC server configuration still require live verification.
- BARQ Brain's chat and knowledge retrieval foundation is not the same as repository editing, command execution, autonomous testing/building, or durable background execution.
- The ARM64-only Galaxy S7 Admin APK build was started in workflow run `45307180610`; at the last verified check, analyze/tests had passed and the ARM64 APK build step was still in progress. Do not claim artifact upload or smaller final size until confirmed.
- Earlier universal Admin debug APK was about 162 MB and was not tested on a physical S7.
- Consumer app physical-device and carrier/network testing remains a separate acceptance requirement.
- Public consumer registration/onboarding and News are deferred to the final consumer roadmap phase.
