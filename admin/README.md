# BARQ Admin foundation

This directory is a separate Admin service boundary. It is not part of the BARQ consumer API and has no production binding.

## Current foundation

- Owner-scoped workspace bootstrap.
- Task creation/listing with idempotency keys.
- Durable task states, server Queue consumer, lease-based task claiming, bounded retries, server-side BARQ Brain draft generation, and optimistic checkpoint versions.
- Append-only audit events enforced by SQLite triggers.
- Explicit approval records in the schema.
- Google OpenID Connect identity exchange using Authorization Code + PKCE in the native client; the Worker verifies Google RS256 signatures, issuer, audience, verified email, exact owner subject, expiry, and one-time nonce use.\n- Short-lived Admin access JWTs bound to a server-side device session; opaque refresh tokens are stored only as SHA-256 hashes and rotated on every use.\n- Owner device inventory, per-device revocation, global session revocation, refresh replay detection, and append-only security audit events.
- Versioned project knowledge ingestion API and an initial guarded GitHub repository indexing script.
- Unit tests and isolated SQLite schema checks.

## Required runtime bindings

The future dedicated Admin Preview Worker requires:

- `ADMIN_DB`: a dedicated Admin Preview D1 database (never the BARQ production D1).
- `ADMIN_TASK_QUEUE`: a dedicated Cloudflare Queue for durable background tasks.
- `ADMIN_AI`: a server-side Workers AI binding used by BARQ Brain for analysis and draft generation.
- `BARQ_ADMIN_JWT_SECRET`: a server-side HS256 secret of at least 32 characters.\n- `BARQ_GOOGLE_OIDC_CLIENT_ID`: the Google OAuth client ID registered for the native BARQ Admin Android app.\n- `BARQ_ADMIN_OWNER_SUBJECT`: the exact Google OIDC `sub` of the one permitted owner; do not use an email address as the primary identity key.
- `BARQ_ADMIN_OWNER_SUBJECT`: the exact owner subject allowed to administer this workspace.
- `BARQ_ADMIN_ALLOWED_ORIGIN`: the exact Admin client origin; no wildcard origin is supported.

The mobile app performs Google Authorization Code + PKCE using AppAuth and sends the Google ID token plus its OIDC nonce to `POST /v1/auth/exchange`. The Worker validates the token against Google signing keys and the configured client ID, then issues a 10-minute Admin access token and a 30-day rotating opaque refresh token. Every API request checks the associated session and device are still active. Refresh-token replay revokes that session. Google client IDs are public identifiers; `BARQ_ADMIN_JWT_SECRET` remains server-only and must never be embedded in an APK. Do not deploy until Google credentials, the exact owner subject, dedicated Preview resources, key rotation, and rate limiting are configured and reviewed.

## API surface

- `GET /health`
- `POST /v1/auth/exchange`, `POST /v1/auth/refresh`, `POST /v1/auth/logout`\n- `GET /v1/devices`, `DELETE /v1/devices/:id`, `POST /v1/devices/revoke-all`\n- `GET /v1/workspace`
- `GET /v1/tasks`
- `POST /v1/tasks` (supports `X-Idempotency-Key`)
- `POST /v1/tasks/:id/checkpoints` (requires `expectedVersion`)
- `PATCH /v1/tasks/:id/status` (validated state transitions)
- `PATCH /v1/workspace` (optimistic project/phase position sync)
- `GET /v1/approvals`, `POST /v1/approvals`, `PATCH /v1/approvals/:id` (owner-reviewed action previews)
- `GET /v1/knowledge`, `POST /v1/knowledge`, `GET /v1/knowledge/:id` (versioned project source index)
- `POST /v1/brain/vision` (owner-provided JPEG/PNG/WebP image analysis; max 3 requests per minute per workspace)
- `POST /v1/brain/generate-image` (prompt-to-JPEG generation through Workers AI; max 2 requests per minute per workspace)
- `GET /v1/audit` (latest append-only audit events)

Image handling is deliberately transient: image-analysis and image-generation payloads are not stored in Admin D1. The image-generation endpoint validates the model response as canonical JPEG base64, enforces an 8 MiB output ceiling, and records only audit metadata (model, byte count, and prompt length). The mobile app previews generated output and opens the platform share sheet; it does not deliver images automatically or retain a permanent image gallery. Real generation requires the dedicated Preview `ADMIN_AI` binding and any model terms acceptance required by Cloudflare.

The checkpoint API stores step input/output references, completed step, next action, and monotonically increasing version. Clients must reload after a version conflict rather than overwrite a newer checkpoint. BARQ Brain retrieves relevant indexed sources by task terms and cites their source paths/revisions. An initial GitHub indexing script now reads an explicit repository ref, skips sensitive paths and likely secret content, limits file sizes and per-run file count, and posts versioned chunks to the Admin API. It has not yet been run against a configured Admin Preview environment.

## Still incomplete

The Queue consumer and server-side assistant draft path exist in code, but dedicated Admin Preview Queue, D1, AI bindings, and end-to-end execution have not been configured or verified. Lease heartbeat/renewal, recovery after worker termination, and dead-letter monitoring remain incomplete. BARQ Brain currently drafts and checkpoints a result; it does not autonomously modify repositories or deploy services. Cross-device session management, push notifications, production-grade owner identity/token issuance, key rotation, rate limiting, and the growth workspace remain follow-on work. No production data or services are changed by this foundation.

## Flutter owner app (initial client shell)

The independent Flutter client is under `admin/mobile`. It includes an Arabic RTL owner dashboard, task list, approvals view, secure token storage, cached workspace/task/approval snapshots, and a local outbox for tasks created while offline. The outbox synchronizes with the server on the next successful app refresh/resume.

Important offline boundary: a task created while the phone has no connection remains a local draft until it can reach the Admin API. Once a task has been accepted by the server queue, its analysis/drafting work runs server-side and can continue while the phone is offline. The owner sign-in flow uses Google OIDC Authorization Code + PKCE. Device/session controls are exposed by the Admin API; the mobile device-management screen and end-to-end Android callback validation remain to be completed and tested.
