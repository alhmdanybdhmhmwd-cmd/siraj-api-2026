# BARQ Brain repository indexing runbook
> **Project separation:** The current approved repository contains both BARQ and BARQ Admin. Brain retrieval must use the selected workspace project: `admin/**` sources are BARQ Admin-only, non-`admin/**` sources are BARQ-only, and `admin/knowledge/BARQ_OWNER_CONTEXT.md` is the sole shared owner-decision seed. Verify this path classifier when repository layout changes; never broaden it silently.


This procedure indexes an explicitly selected GitHub repository revision into BARQ Brain's `admin_project_knowledge` tables. The selected architecture uses the existing BARQ Worker and D1 database through the isolated `/admin/*` route; it does not read or index consumer user, message, or SPARK records.

## Required runtime configuration

Supply these values only through a trusted local secret manager or protected CI secrets. Never commit them, paste them into chat, or print them in logs.

- `BARQ_ADMIN_GITHUB_REPOSITORY`: owner/repository, for example the BARQ engineering repository.
- `BARQ_ADMIN_GITHUB_ALLOWED_REPOSITORIES`: semicolon-separated exact owner/repository allowlist approved for this indexing run. The selected repository must match one entry exactly; wildcards and implicit access to other repositories are not accepted.
- `BARQ_ADMIN_GITHUB_REF`: immutable commit SHA preferred; a branch or tag is acceptable when the resolved SHA is recorded.
- `BARQ_ADMIN_GITHUB_TOKEN`: read-only GitHub Contents/Metadata access for the selected repository.
- `BARQ_ADMIN_API_URL`: HTTPS base URL of the existing BARQ Worker with the `/admin` prefix, for example `https://<existing-worker-host>/admin` (do not use the root URL or invent a host).
- `BARQ_ADMIN_OWNER_TOKEN`: short-lived owner access token accepted by the shared Admin route.
- `BARQ_ADMIN_GITHUB_START_AFTER`: optional path cursor, initially empty.

The shared BARQ Worker must have the additive Admin migrations applied to its existing D1 database, plus the separate Admin JWT secret, Google owner allowlist, and exact Admin origin configured. The indexer appends `/v1/knowledge` to `BARQ_ADMIN_API_URL`, producing the shared endpoint `/admin/v1/knowledge`. Do not apply migrations or deploy the shared Worker until the owner explicitly approves that live production change.

## Run and resume

From the `admin/` directory:

```sh
npm run knowledge:ingest
```

The command prints a JSON summary with the resolved immutable revision, indexed chunk count, skipped reasons, batch cursor, batch completion, and (after the final batch) a paginated reconciliation report for current, stale, deleted, and incomplete sources.

- If `complete` / `batchComplete` is `true`, the current revision's eligible file batches have been processed; this alone does not prove complete or fresh knowledge coverage.
- After the final batch, the indexer automatically reads every indexed-source page for the approved repository and emits a reconciliation report.
- `coverageComplete` is `true` only when every current eligible file has all expected chunks and there are no stale-revision or deleted-source records. Otherwise inspect `reconciliation` and `requiresOwnerReview`; no indexed records are deleted automatically.
- If `batchComplete` is `false`, set `BARQ_ADMIN_GITHUB_START_AFTER` to the returned `nextStartAfter` value and run again.
- Keep the repository and commit SHA unchanged across resumed batches.
- If any batch fails, rerun it with the same cursor; source rows are upserted by workspace, repository-qualified path, and revision.
- A new commit requires a new full indexing pass. Reconciliation compares the current eligible tree with every paginated indexed source and reports stale revisions, paths missing from the current tree, files not yet indexed, and incomplete chunks. A rename is conservatively represented as an old path missing plus a new path not yet indexed; the current report does not claim a semantic rename match. No stale/deleted records are removed automatically, and no cleanup is implied.

## Completion evidence

Record repository, resolved commit SHA, batch count, indexed chunks, skipped files, final `complete=true`, run time, and any provider/API errors. Do not claim full BARQ project coverage until every required repository and approved owner-context source is indexed and a separate coverage/freshness report verifies it.

The indexer requires an explicit exact repository allowlist, excludes configured sensitive paths and likely secret patterns, and records the resolved commit SHA. These controls are defense in depth, not a guarantee that arbitrary repository content is safe. Review repository scope and keep credentials, signing keys, tokens, and private user data out of the index.


## Reconciliation limits — 2026-11-28

- The current implementation verifies repository path presence and chunk completeness against a resolved immutable commit, after fetching every indexed-source page. It does not infer semantic renames, because the indexed listing does not yet expose content fingerprints for safe old/new path matching.
- A renamed file is therefore visible as both a missing old path and a not-yet-indexed new path until the new revision is ingested. This is an explicit review signal, not a data-loss event.
- Stale revisions and paths missing from the current tree remain in the knowledge store for audit/history. Do not add automatic deletion or overwrite historical evidence as part of Phase 5.
- Coverage verification is limited to eligible source files under the current path/size/extension policy. Skipped paths and reasons must remain visible in the ingestion summary; coverage is not a claim about excluded or unapproved repositories.
