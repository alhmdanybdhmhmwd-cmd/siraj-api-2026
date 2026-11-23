# BARQ Admin foundation

This directory is a separate Admin service boundary. It is not part of the BARQ consumer API and has no production binding.

## Current foundation

- Owner-scoped workspace bootstrap.
- Task creation/listing with idempotency keys.
- Durable task states, server Queue consumer, lease-based task claiming, bounded retries, server-side BARQ Brain draft generation, and optimistic checkpoint versions.
- Append-only audit events enforced by SQLite triggers.
- Explicit approval records in the schema.
- Google OpenID Connect identity exchange using Authorization Code + PKCE in the native client; the Worker verifies Google RS256 signatures, issuer, audience, verified email, exact owner subject, expiry, and one-time nonce use.
- Short-lived Admin access JWTs bound to a server-side device session; opaque refresh tokens are stored only as SHA-256 hashes and rotated on every use; a hash history distinguishes a genuine replay from an arbitrary invalid token, so random bad tokens cannot revoke an owner session.
- Owner device inventory, per-device revocation, global session revocation, refresh replay detection, and append-only security audit events.
- Versioned project knowledge ingestion API and an initial guarded GitHub repository indexing script.
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

A non-production configuration template is provided at `wrangler.toml.example`. From the `admin/` directory, the operator must create a dedicated Preview D1 database and two dedicated Queues (`barq-admin-preview-tasks` and `barq-admin-preview-dlq`), copy the example to `wrangler.toml`, replace every placeholder (especially the D1 database ID and exact allowed client origin), and configure the server-only JWT secret with `npx wrangler secret put BARQ_ADMIN_JWT_SECRET`. Apply only the Admin migrations with `npx wrangler d1 migrations apply barq-admin-preview --remote`. Deploy the Preview Worker only after reviewing the bindings and verifying that no BARQ production resource IDs are present. The template is intentionally not deployable until real dedicated resource identifiers and owner configuration are supplied; no resources or secrets have been created by committing this template.

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
- `POST /v1/brain/vision` (owner-provided JPEG/PNG/WebP image analysis; no application-imposed request-count quota)
- `POST /v1/brain/generate-image` (prompt-to-JPEG generation through Workers AI; no application-imposed request-count quota)
- `GET /v1/audit` (latest append-only audit events)

Image handling is deliberately transient: image-analysis and image-generation payloads are not stored in Admin D1. There are no daily, per-minute, or lifetime request-count caps imposed by the application for image analysis or image generation. Requests remain subject to the configured AI provider's availability, account-level service limits, and technical payload-size validation; these are not usage-count quotas. The image-generation endpoint validates the model response as canonical JPEG base64, enforces an 8 MiB output ceiling, and records only audit metadata (model, byte count, and prompt length). The mobile app previews generated output and opens the platform share sheet; it does not deliver images automatically or retain a permanent image gallery. Real generation requires the dedicated Preview `ADMIN_AI` binding and any model terms acceptance required by Cloudflare.

The checkpoint API stores step input/output references, completed step, next action, and monotonically increasing version. Clients must reload after a version conflict rather than overwrite a newer checkpoint. BARQ Brain retrieves relevant indexed sources by task terms and cites their source paths/revisions. An initial GitHub indexing script now reads an explicit repository ref, skips sensitive paths and likely secret content, limits file sizes and per-run file count, and posts versioned chunks to the Admin API. It has not yet been run against a configured Admin Preview environment.

## Still incomplete

- The Google OIDC exchange, Admin session issuance, refresh rotation, logout, device listing, and revocation routes are implemented in the isolated Worker code and covered by unit/schema checks. They have **not** yet been exercised against a configured Google OAuth client and dedicated Admin Preview resources or on a physical Android device.
- The mobile client includes Google OIDC login, secure token storage, refresh handling, logout, and a device-management dialog. Android callback behavior still needs a real signed build/device acceptance test.
- Dedicated Admin Preview D1, Queue, and AI bindings are not configured or verified. The Queue consumer and server-side assistant draft path exist in code, but lease heartbeat/renewal, recovery after worker termination, and dead-letter monitoring remain incomplete.
- BARQ Brain currently drafts and checkpoints a result; it does not autonomously modify repositories or deploy services. Push notifications, signing-key rotation procedures, concurrency-focused refresh tests, and the growth workspace remain follow-on work.

No production data or services are changed by this foundation. The current CI pass validates syntax, unit tests, schema invariants, Flutter analysis/tests, and Android manifest/Gradle AppAuth wiring; it does not prove live Google sign-in or deployed background execution.

## Flutter owner app (initial client shell)

The Flutter sources are formatted with the repository formatter; CI enforces `dart format --output=none --set-exit-if-changed` before analysis and tests. The temporary formatter workflow has been removed after dependency-aware formatting.

The independent Flutter client is under `admin/mobile`. It includes an Arabic RTL owner dashboard, task list, approvals view, secure token storage, cached workspace/task/approval snapshots, and a local outbox for tasks created while offline. The outbox synchronizes with the server on the next successful app refresh/resume.

Important offline boundary: a task created while the phone has no connection remains a local draft until it can reach the Admin API. Once a task has been accepted by the server queue, its analysis/drafting work runs server-side and can continue while the phone is offline. The owner sign-in flow uses Google OIDC Authorization Code + PKCE. The mobile device-management dialog and corresponding API routes are implemented; end-to-end Android callback and live session-revocation behavior remain to be tested against configured Preview resources.

## Owner requirement: always-on BARQ monitoring and safe self-repair (future phase)

The owner explicitly requires BARQ Admin to monitor the BARQ service independently of the owner's phone and internet connection. This is a required future capability, not a feature currently deployed or claimed as operational.

The implementation must run from continuously available server-side monitoring and background workers, collect service health and authorized error/diagnostic signals, detect incidents, correlate them with recent changes, and create a durable incident/task record. For eligible code or configuration faults, BARQ Brain may prepare and apply a repair in an isolated branch or preview environment, run focused and regression tests, and retry within bounded limits. It must retain an audit trail and report the incident, attempted repair, test evidence, and outcome when the owner reconnects.

Autonomous repair must not mean unrestricted production access. Production deployment, destructive data changes, secret or permission changes, paid actions, and public communications remain approval-gated. Where a safe repair cannot be verified, the system must stop, preserve evidence, and request owner review rather than guess. The phone is a notification and control surface; monitoring and accepted server-side work must not depend on the phone remaining online. Work created offline on the phone remains a local draft until synchronized.

This requirement belongs to the later durable-operation and end-to-end lifecycle phases. Phase 1 remains limited to completing the secure Admin foundation and validating its dedicated Preview setup; do not start BARQ repository analysis or autonomous repair implementation before the owner authorizes the relevant phase.
