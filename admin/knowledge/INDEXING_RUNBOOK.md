# BARQ Brain repository indexing runbook

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

The command prints a JSON summary with the resolved repository revision, indexed chunk count, skipped file count, eligible files in the current batch, remaining files, completion status, and `nextStartAfter`.

- If `complete` is `true`, that repository revision's eligible file set has been processed.
- If `complete` is `false`, set `BARQ_ADMIN_GITHUB_START_AFTER` to the returned `nextStartAfter` value and run again.
- Keep the repository and commit SHA unchanged across resumed batches.
- If any batch fails, rerun it with the same cursor; source rows are upserted by workspace, repository-qualified path, and revision.
- A new commit requires a new full indexing pass. Removed/renamed files and stale-source cleanup still need a dedicated reconciliation process; do not infer they were deleted from the index.

## Completion evidence

Record repository, resolved commit SHA, batch count, indexed chunks, skipped files, final `complete=true`, run time, and any provider/API errors. Do not claim full BARQ project coverage until every required repository and approved owner-context source is indexed and a separate coverage/freshness report verifies it.

The indexer requires an explicit exact repository allowlist, excludes configured sensitive paths and likely secret patterns, and records the resolved commit SHA. These controls are defense in depth, not a guarantee that arbitrary repository content is safe. Review repository scope and keep credentials, signing keys, tokens, and private user data out of the index.
