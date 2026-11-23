# BARQ Admin foundation

This directory is a separate Admin service boundary. It is not part of the BARQ consumer API and has no production binding.

## Current foundation

- Owner-scoped workspace bootstrap.
- Task creation/listing with idempotency keys.
- Durable task states, server Queue consumer, lease-based task claiming, bounded retries, server-side BARQ Brain draft generation, and optimistic checkpoint versions.
- Append-only audit events enforced by SQLite triggers.
- Explicit approval records in the schema.
- Owner-only JWT validation. The owner subject is configured server-side; a client cannot grant itself a role.
- Versioned project knowledge ingestion API and an initial guarded GitHub repository indexing script.
- Unit tests and isolated SQLite schema checks.

## Required runtime bindings

The future dedicated Admin Preview Worker requires:

- `ADMIN_DB`: a dedicated Admin Preview D1 database (never the BARQ production D1).
- `ADMIN_TASK_QUEUE`: a dedicated Cloudflare Queue for durable background tasks.
- `ADMIN_AI`: a server-side Workers AI binding used by BARQ Brain for analysis and draft generation.
- `BARQ_ADMIN_JWT_SECRET`: a server-side HS256 secret of at least 32 characters.
- `BARQ_ADMIN_OWNER_SUBJECT`: the exact owner subject allowed to administer this workspace.
- `BARQ_ADMIN_ALLOWED_ORIGIN`: the exact Admin client origin; no wildcard origin is supported.

Accepted bearer tokens must be issued by a trusted server-side identity component with `iss=barq-admin-auth`, `aud=barq-admin`, an exact owner `sub`, and a valid integer `exp`. This repository change does not create a token issuer or embed credentials in an APK. Do not deploy until the issuer, device-session revocation, key rotation, rate limiting, and dedicated Preview resources are configured and reviewed.

## API surface

- `GET /health`
- `GET /v1/workspace`
- `GET /v1/tasks`
- `POST /v1/tasks` (supports `X-Idempotency-Key`)
- `POST /v1/tasks/:id/checkpoints` (requires `expectedVersion`)
- `PATCH /v1/tasks/:id/status` (validated state transitions)
- `PATCH /v1/workspace` (optimistic project/phase position sync)
- `GET /v1/approvals`, `POST /v1/approvals`, `PATCH /v1/approvals/:id` (owner-reviewed action previews)
- `GET /v1/knowledge`, `POST /v1/knowledge`, `GET /v1/knowledge/:id` (versioned project source index)
- `POST /v1/brain/vision` (owner-provided JPEG/PNG/WebP image analysis; bounded input and per-workspace rate limit)
- `POST /v1/brain/generate-image` (prompt-to-JPEG generation through Workers AI; two requests per minute per workspace)
- `GET /v1/audit` (latest append-only audit events)

Image handling is deliberately transient: image-analysis and image-generation payloads are not stored in Admin D1. The image-generation endpoint validates the model response as canonical JPEG base64, enforces an 8 MiB output ceiling, and records only audit metadata (model, byte count, and prompt length). The mobile app previews generated output and opens the platform share sheet; it does not deliver images automatically or retain a permanent image gallery. Real generation requires the dedicated Preview `ADMIN_AI` binding and any model terms acceptance required by Cloudflare.

The checkpoint API stores step input/output references, completed step, next action, and monotonically increasing version. Clients must reload after a version conflict rather than overwrite a newer checkpoint. BARQ Brain retrieves relevant indexed sources by task terms and cites their source paths/revisions. An initial GitHub indexing script now reads an explicit repository ref, skips sensitive paths and likely secret content, limits file sizes and per-run file count, and posts versioned chunks to the Admin API. It has not yet been run against a configured Admin Preview environment.

## Still incomplete

The Queue consumer and server-side assistant draft path exist in code, but dedicated Admin Preview Queue, D1, AI bindings, and end-to-end execution have not been configured or verified. Lease heartbeat/renewal, recovery after worker termination, and dead-letter monitoring remain incomplete. BARQ Brain currently drafts and checkpoints a result; it does not autonomously modify repositories or deploy services. Cross-device session management, push notifications, production-grade owner identity/token issuance, key rotation, rate limiting, and the growth workspace remain follow-on work. No production data or services are changed by this foundation.

## Flutter owner app (initial client shell)

The independent Flutter client is under `admin/mobile`. It includes an Arabic RTL owner dashboard, task list, approvals view, secure token storage, cached workspace/task/approval snapshots, and a local outbox for tasks created while offline. The outbox synchronizes with the server on the next successful app refresh/resume.

Important offline boundary: a task created while the phone has no connection remains a local draft until it can reach the Admin API. Once a task has been accepted by the server queue, its analysis/drafting work runs server-side and can continue while the phone is offline. The current client uses a temporary owner-session-token setup screen; a proper owner sign-in/token issuer and device-session revocation are not implemented yet.
