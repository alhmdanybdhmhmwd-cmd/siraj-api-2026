# BARQ Admin foundation

This directory is a separate Admin service boundary. It is not part of the BARQ consumer API and has no production binding.

## Current foundation

- Owner-scoped workspace bootstrap.
- Task creation/listing with idempotency keys.
- Durable task states, server Queue consumer, lease-based task claiming, bounded retries, server-side BARQ Brain draft generation, and optimistic checkpoint versions. The Preview Queue is configured for one message per delivery. A dedicated dead-letter consumer marks exhausted queued/running tasks as failed, clears their lease, and writes an audit event for owner review.
- Append-only audit events enforced by SQLite triggers.
- Explicit approval records in the schema.
- Google OpenID Connect identity exchange using Authorization Code + PKCE in the native client; the Worker verifies Google RS256 signatures, issuer, audience, verified email, exact owner subject, expiry, and one-time nonce use.
- Short-lived Admin access JWTs bound to a server-side device session; opaque refresh tokens are stored only as SHA-256 hashes and rotated on every use; a hash history distinguishes a genuine replay from an arbitrary invalid token, so random bad tokens cannot revoke an owner session.
- Owner device inventory, per-device revocation, global session revocation, refresh replay detection, and append-only security audit events.
- Versioned project knowledge ingestion API and guarded GitHub repository indexing for Markdown, source code, Android manifests/Gradle files, SQL migrations, CI workflows, and project scripts. Phase 2 is explicitly owner-authorized; the assistant is instructed to distinguish accepted/rejected/postponed decisions, cite exact source paths/revisions, report missing coverage, and treat indexed content as untrusted reference data.
- Unit tests and isolated SQLite schema checks.

## Required runtime bindings

The future dedicated Admin Preview Worker requires:

- `ADMIN_DB`: a dedicated Admin Preview D1 database (never the BARQ production D1).
- `ADMIN_TASK_QUEUE`: a dedicated Cloudflare Queue for durable background tasks.
- `ADMIN_AI`: a server-side Workers AI binding used by BARQ Brain for analysis and draft generation.
- `BARQ_ADMIN_JWT_SECRET`: a server-side HS256 secret of at least 32 characters.
- `BARQ_GOOGLE_OIDC_CLIENT_ID`: the Google OAuth client ID registered for the native BARQ Admin Android app.
- `BARQ_ADMIN_OWNER_SUBJECT`: the exact Google OIDC `sub` of the one permitted owner; do not use an email address as the primary identity key.
- `BARQ_ADMIN_OWNER_EMAIL`: the exact verified Google email allowed to administer this workspace. Optionally pin `BARQ_ADMIN_OWNER_SUBJECT` after first enrollment.
- `BARQ_ADMIN_ALLOWED_ORIGIN`: the exact Admin client origin; no wildcard origin is supported.

A non-production configuration template is provided at `wrangler.toml.example`. From the `admin/` directory:

1. Create the isolated D1 database: `npx wrangler d1 create barq-admin-preview`. Copy the returned database ID into the template's `database_id`.
2. Create both queues: `npx wrangler queues create barq-admin-preview-tasks` and `npx wrangler queues create barq-admin-preview-dlq`.
3. Copy `wrangler.toml.example` to `wrangler.toml` and replace every placeholder, including the exact allowed client origin, Google client ID, verified owner email, and D1 ID. Never use a BARQ consumer-production resource ID.
4. Store the JWT secret only as a protected GitHub Actions Environment secret named `BARQ_ADMIN_JWT_SECRET` when using the guarded Preview workflow; the workflow transfers it directly to Cloudflare with `wrangler secret put`. Never commit it, place it in TOML or ordinary repository variables, print it in logs, or embed it in the APK. For manual deployment, enter it interactively with `npx wrangler secret put BARQ_ADMIN_JWT_SECRET`.
5. Apply only the Admin migrations to the dedicated database: `npx wrangler d1 migrations apply barq-admin-preview --remote`.
6. Review the final bindings and resource IDs, then deploy the Preview Worker with `npx wrangler deploy`. Verify `/health` and confirm the auth exchange is unavailable until owner configuration is correct.

The template is intentionally not deployable until real dedicated resource identifiers and owner configuration are supplied; no resources or secrets have been created by committing this template.

The mobile app performs Google Authorization Code + PKCE using AppAuth and sends the Google ID token plus its OIDC nonce to `POST /v1/auth/exchange`. Configure `BARQ_GOOGLE_OIDC_CLIENT_ID`, the exact verified `BARQ_ADMIN_OWNER_EMAIL`, and a 32+ character server-only `BARQ_ADMIN_JWT_SECRET`. Optionally pin the Google subject in `BARQ_ADMIN_OWNER_SUBJECT` after first enrollment. The Worker validates the token against Google signing keys and the configured client ID, then issues a 10-minute Admin access token and a 30-day rotating opaque refresh token. Every API request checks the associated session and device are still active. Refresh-token replay revokes that session. Google client IDs are public identifiers; `BARQ_ADMIN_JWT_SECRET` remains server-only and must never be embedded in an APK. Sign-in exchanges are limited to five attempts per minute per source IP and refreshes to ten per minute per session; these are short-window abuse controls, not daily quotas. Do not deploy until Google credentials, the exact owner email, dedicated Preview resources, key rotation, and rate limiting are configured and reviewed.

## API surface

- `GET /health`
- `POST /v1/auth/exchange`, `POST /v1/auth/refresh`, `POST /v1/auth/logout`
- `GET /v1/devices`, `DELETE /v1/devices/:id`, `POST /v1/devices/revoke-all`
- `GET /v1/workspace`
- `GET /v1/tasks`
- `POST /v1/tasks` (supports `X-Idempotency-Key`)
- `POST /v1/tasks/:id/checkpoints` (requires `expectedVersion`)
- `PATCH /v1/tasks/:id/status` (validated state transitions)
- `PATCH /v1/workspace` (optimistic project/phase position sync)
- `GET /v1/approvals`, `POST /v1/approvals`, `PATCH /v1/approvals/:id` (owner-reviewed action previews)
- `GET /v1/knowledge`, `POST /v1/knowledge`, `GET /v1/knowledge/:id` (versioned project source index)
- `GET /v1/brain/conversations`, `POST /v1/brain/chat`, `GET /v1/brain/conversations/:id/messages` (owner-scoped persistent assistant conversations with source references)
- `POST /v1/brain/vision` (owner-provided JPEG/PNG/WebP image analysis; no application-imposed request-count quota)
- `POST /v1/brain/generate-image` (prompt-to-JPEG generation through Workers AI; no application-imposed request-count quota)
- `GET /v1/audit` (latest append-only audit events)

Image handling is deliberately transient: image-analysis and image-generation payloads are not stored in Admin D1. There are no daily, per-minute, or lifetime request-count caps imposed by the application for image analysis or image generation. Requests remain subject to the configured AI provider's availability, account-level service limits, and technical payload-size validation; these are not usage-count quotas. The image-generation endpoint validates the model response as canonical JPEG base64, enforces an 8 MiB output ceiling, and records only audit metadata (model, byte count, and prompt length). The mobile app previews generated output and opens the platform share sheet; it does not deliver images automatically or retain a permanent image gallery. Real generation requires the dedicated Preview `ADMIN_AI` binding and any model terms acceptance required by Cloudflare.

The checkpoint API stores step input/output references, completed step, next action, and monotonically increasing version. Clients must reload after a version conflict rather than overwrite a newer checkpoint. BARQ Brain retrieves relevant indexed sources using bounded multilingual terms, searches title/path/content rather than only the newest 200 records, ranks title and path evidence above body matches, and instructs the model to cite only supplied numbered sources with exact paths/revisions. The GitHub indexer reads an explicit repository ref, supports source types, chunks long files, skips sensitive paths and likely secret content, and posts versioned chunks to the Admin API. It now includes Android XML/Gradle/Kotlin build files and Python/shell CI tooling in its safe file allowlist. The indexer reports eligible, processed, skipped, remaining, and complete counts instead of silently implying full coverage when the 300-file run cap is reached. It supports resumable alphabetical batches through `BARQ_ADMIN_GITHUB_START_AFTER`; use the returned `nextStartAfter` value for the next run until `complete` is true. Source paths are repository-qualified to avoid collisions. Indexing has not yet been run against a configured Admin Preview environment; repository coverage and freshness remain unverified until then.

## Still incomplete

- The Google OIDC exchange, Admin session issuance, refresh rotation, logout, device listing, and revocation routes are implemented in the isolated Worker code and covered by unit/schema checks. They have **not** yet been exercised against a configured Google OAuth client and dedicated Admin Preview resources or on a physical Android device.
- The mobile client includes Google OIDC login, secure token storage, refresh handling, logout, and a device-management dialog. Android callback behavior still needs a real signed build/device acceptance test.
- Dedicated Admin Preview D1, Queue, and AI bindings are not configured or verified. The Queue consumer now processes one task per delivery and a dedicated dead-letter consumer marks exhausted tasks failed and records an audit event. Lease renewal during long AI calls now runs every four minutes with ownership fencing before completion. Explicit recovery/requeue after abrupt worker termination remains incomplete; queue-depth/age alerting and a dead-letter monitoring dashboard are also not implemented.
- BARQ Brain supports persistent owner-scoped chat history and source-referenced replies in addition to durable task drafts/checkpoints. It does not autonomously modify repositories or deploy services. Chat requires the dedicated Preview `ADMIN_AI` binding and the new `0007_brain_conversations.sql` migration. Push notifications, signing-key rotation procedures, concurrency-focused refresh tests, and the growth workspace remain follow-on work.

No production data or services are changed by this foundation. The current CI pass validates syntax, unit tests, schema invariants, Flutter analysis/tests, and Android manifest/Gradle AppAuth wiring; it does not prove live Google sign-in or deployed background execution.

## Flutter owner app (initial client shell)

The Flutter sources are formatted with the repository formatter; CI enforces `dart format --output=none --set-exit-if-changed` before analysis and tests. The temporary formatter workflow has been removed after dependency-aware formatting.

The independent Flutter client is under `admin/mobile`. It includes an Arabic RTL owner dashboard, task list, approvals view, secure token storage, cached workspace/task/approval snapshots, and a local outbox for tasks created while offline. The outbox synchronizes with the server on the next successful app refresh/resume.

Important offline boundary: a task created while the phone has no connection remains a local draft until it can reach the Admin API. Once a task has been accepted by the server queue, its analysis/drafting work runs server-side and can continue while the phone is offline. The owner sign-in flow uses Google OIDC Authorization Code + PKCE. The mobile device-management dialog and corresponding API routes are implemented; end-to-end Android callback and live session-revocation behavior remain to be tested against configured Preview resources.

## Owner requirement: complete BARQ project understanding for BARQ Brain (Phase 2)

The owner requires BARQ Brain to become a broad, project-aware engineering assistant for the separate BARQ Admin app. It must understand the BARQ product and its development history well enough for the owner to continue building BARQ together with the assistant, rather than behaving as a generic chatbot.

This is an explicit Phase 2 acceptance requirement. The owner explicitly authorized Phase 2 on 2026-11-24; repository indexing, project analysis, and BARQ Brain implementation are now in progress. The earlier Phase 1-only restriction is superseded. Do not claim complete project understanding until configured sources have actually been indexed and coverage/freshness checks pass.

When Phase 2 is authorized, the knowledge system must progressively cover and keep current:

- Product identity, purpose, global audience, product vision, user journeys, and the distinction between BARQ (the messaging app), SPARK (its stories/status feature), BARQ Admin (the management app), and BARQ Brain (the Admin assistant).
- The agreed roadmap, phase boundaries, completed and pending work, owner-approved decisions, changed or rejected ideas, and constraints that must not be reintroduced.
- Every major BARQ feature and its behavior, UI flows, interactions, permissions, dependencies, and relationships to other features.
- All authorized project repositories and relevant branches, source files, commits, pull requests, issues, release notes, and configuration. Repository scope must be explicit and owner-approved.
- System architecture, Android/mobile structure, backend services, Workers, databases and migrations, APIs/contracts, authentication, notifications, storage, deployment environments, and third-party integrations.
- Known and historical defects, error evidence, root-cause hypotheses, attempted fixes, test outcomes, regressions, operational incidents, and unresolved risks.
- CI workflows, unit/integration/device tests, build results, deployment/health evidence, and the exact revision each result applies to.

Knowledge must be source-backed and revision-aware: retain source path or record ID, repository/ref/commit or other revision, observed time, and ingestion status. Distinguish verified facts from assumptions and outdated material; surface conflicts instead of silently choosing one. Preserve an owner decision/history ledger so a later conversation does not erase or contradict earlier approved requirements. Refresh changed sources incrementally, detect removals/renames, and show what has not yet been indexed. Retrieve relevant material across sources for each task and cite the source and revision in answers.

Phase 2 acceptance must include a coverage report, freshness/staleness indicators, source citations, tests for retrieval and conflicting decisions, and a demonstration that BARQ Brain can explain the product architecture, roadmap, feature behavior, known problems, and next authorized work without inventing missing facts. Do not claim it knows "everything" until the configured sources have actually been indexed and coverage has been measured. Keep secrets, personal user data, and production credentials out of the knowledge index.

## Owner requirement: always-on BARQ monitoring and safe self-repair (future phase)

The owner explicitly requires BARQ Admin to monitor the BARQ service independently of the owner's phone and internet connection. This is a required future capability, not a feature currently deployed or claimed as operational.

The implementation must run from continuously available server-side monitoring and background workers, collect service health and authorized error/diagnostic signals, detect incidents, correlate them with recent changes, and create a durable incident/task record. For eligible code or configuration faults, BARQ Brain may prepare and apply a repair in an isolated branch or preview environment, run focused and regression tests, and retry within bounded limits. It must retain an audit trail and report the incident, attempted repair, test evidence, and outcome when the owner reconnects.

Autonomous repair must not mean unrestricted production access. Production deployment, destructive data changes, secret or permission changes, paid actions, and public communications remain approval-gated. Where a safe repair cannot be verified, the system must stop, preserve evidence, and request owner review rather than guess. The phone is a notification and control surface; monitoring and accepted server-side work must not depend on the phone remaining online. Work created offline on the phone remains a local draft until synchronized.

This requirement belongs to the later durable-operation and end-to-end lifecycle phases. The owner has authorized Phase 2 project understanding and knowledge indexing. Phase 1 secure-foundation closeout continues in parallel. Autonomous repository repair, editing, merging, production deployment, and durable independent operation remain outside Phase 2 and require later phase authorization.
