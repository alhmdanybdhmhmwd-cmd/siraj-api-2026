# BARQ Brain repository indexing runbook

This procedure indexes an explicitly selected GitHub repository revision into the dedicated BARQ Admin Preview knowledge store. It does not target the BARQ consumer database.

## Required runtime configuration

Supply these values only through a trusted local secret manager or protected CI secrets. Never commit them, paste them into chat, or print them in logs.

- `BARQ_ADMIN_GITHUB_REPOSITORY`: owner/repository, for example the BARQ engineering repository.
- `BARQ_ADMIN_GITHUB_ALLOWED_REPOSITORIES`: semicolon-separated exact owner/repository allowlist approved for this indexing run. The selected repository must match one entry exactly; wildcards and implicit access to other repositories are not accepted.
- `BARQ_ADMIN_GITHUB_REF`: immutable commit SHA preferred; a branch or tag is acceptable when the resolved SHA is recorded.
- `BARQ_ADMIN_GITHUB_TOKEN`: read-only GitHub Contents/Metadata access for the selected repository.
- `BARQ_ADMIN_API_URL`: HTTPS URL of the dedicated BARQ Admin Preview Worker.
- `BARQ_ADMIN_OWNER_TOKEN`: short-lived owner access token accepted by the Preview Worker.
- `BARQ_ADMIN_GITHUB_START_AFTER`: optional path cursor, initially empty.

The Preview Worker must have its dedicated Preview D1 binding and owner authentication configured. The indexer requires the owner-scoped `POST /v1/knowledge` API.

## Run and resume

From the `admin/` directory:

```sh
npm run knowledge:ingest
```

The command prints a JSON summary with the resolved repository revision, indexed chunk count, skipped file count, eligible files in the current batch, remaining files, completion status, and `nextStartAfter`.

- If `complete` is `true`, that repository revision's eligible file set has been processed.
- If `complete` is `false`, set `BARQ_ADMIN_GITHUB_START_AFTER` to the returned `nextStartAfter` value and run again.
- Keep the repository and commit SHA unchanged across resumed batches.
- If any batch fails, rerun it with the same cursor; source rows are upserted by workspace, repository-qualified path, and revision.
- A new commit requires a new full indexing pass. Removed/renamed files and stale-source cleanup still need a dedicated reconciliation process; do not infer they were deleted from the index.

## Completion evidence

Record repository, resolved commit SHA, batch count, indexed chunks, skipped files, final `complete=true`, run time, and any provider/API errors. Do not claim full BARQ project coverage until every required repository and approved owner-context source is indexed and a separate coverage/freshness report verifies it.

The indexer requires an explicit exact repository allowlist, excludes configured sensitive paths and likely secret patterns, and records the resolved commit SHA. These controls are defense in depth, not a guarantee that arbitrary repository content is safe. Review repository scope and keep credentials, signing keys, tokens, and private user data out of the index.


## BARQ Brain full-project scope update — 2026-11-24

The owner requires Brain to resume with the full known project context, not only the latest code. The approved monorepo contains the consumer app/backend and the separate Admin app/backend. Keep these areas distinct while indexing the single approved repository:
- Consumer BARQ client: `android/`
- Consumer backend: `src/` and relevant root configuration/workflows
- BARQ Admin client and server: `admin/mobile/`, `admin/worker.js`, `admin/auth.js`, `admin/migrations/`
- Owner decisions and history: `admin/knowledge/BARQ_OWNER_CONTEXT.md`
- Knowledge navigation: `admin/knowledge/BARQ_BRAIN_MASTER_INDEX_AR.md`
- Phase scope and indexing instructions: `admin/knowledge/PHASE2_SCOPE.md`, this runbook
- Historical progress and verification records: `android/BARQ_SIX_FEATURES_STATUS.md`, `android/BARQ_REPAIR_PROGRESS_AR.md`, and other indexed Markdown records
- CI/build/deploy configuration: `.github/workflows/`

Markdown is an eligible index format. The current indexer limits each batch to 300 files, each file to 120,000 bytes, and chunks content at 18,000 characters. It excludes known build/dependency/secret paths and likely secret content. Report skipped paths/counts; do not call the index complete if any eligible batch remains or the GitHub tree is truncated.

The new owner-context and master-index documents have been committed to branch `barq-admin-s7-optimized-2026-11-24`. They are not yet proven ingested into the live Admin D1 store. Before declaring Brain fully informed, run the indexer against the exact immutable commit SHA with the explicit allowlist, resume every batch to `complete=true`, and generate a coverage/freshness report. Then run retrieval tests against representative questions from each domain and confirm the returned source paths/revisions.
