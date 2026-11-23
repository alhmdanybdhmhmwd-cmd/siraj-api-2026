# BARQ Admin foundation

This directory is a separate Admin service boundary. It is not part of the BARQ consumer API and has no production binding.

## Current foundation

- Owner-scoped workspace bootstrap.
- Task creation/listing with idempotency keys.
- Durable task states and optimistic checkpoint versions.
- Append-only audit events enforced by SQLite triggers.
- Explicit approval records in the schema.
- Owner-only JWT validation. The owner subject is configured server-side; a client cannot grant itself a role.
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
- `GET /v1/audit` (latest append-only audit events)

The checkpoint API stores step input/output references, completed step, next action, and monotonically increasing version. Clients must reload after a version conflict rather than overwrite a newer checkpoint. BARQ Brain retrieves relevant indexed sources by task terms and cites their source paths/revisions; source ingestion is currently owner/API-driven, with automatic GitHub repository indexing planned as a later connector.

## Not implemented yet

Durable Queue/worker execution, assistant tool orchestration, project knowledge ingestion, cross-device UI, push notifications, owner approval decision endpoints, device/session management, and the growth-campaign workspace are follow-on work. A queued task is persisted but is not yet executed by a background worker. No production data or services are changed by this foundation.

## Flutter owner app (initial client shell)

The independent Flutter client is under `admin/mobile`. It includes an Arabic RTL owner dashboard, task list, approvals view, secure token storage, cached workspace/task/approval snapshots, and a local outbox for tasks created while offline. The outbox synchronizes with the server on the next successful app refresh/resume.

Important offline boundary: a task created while the phone has no connection remains a local draft until it can reach the Admin API. Once a task has been accepted by the server queue, its analysis/drafting work runs server-side and can continue while the phone is offline. The current client uses a temporary owner-session-token setup screen; a proper owner sign-in/token issuer and device-session revocation are not implemented yet.
