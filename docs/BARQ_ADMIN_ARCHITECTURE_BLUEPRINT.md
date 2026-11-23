# BARQ Admin — Product and Architecture Blueprint

Status: planning baseline only. This document does not deploy services, change production data, or authorize privileged actions.

## Product goal
BARQ Admin is a separate, secure administration app for the BARQ messaging platform. Its embedded assistant, BARQ Brain, should understand the whole BARQ project and help the owner investigate, plan, implement, test, and administer it. The admin app must resume the same work from another phone.

## Non-negotiable multi-device continuity
- The source of truth is a secured server-side workspace, never a single phone's local storage.
- Persist conversations, project context/index references, tasks, task checkpoints, approvals, execution logs, artifacts, and current project/phase position centrally.
- Each task has a durable ID, status, last completed step, next step, inputs/outputs, timestamps, and resumable checkpoint.
- Every device signs in to the same owner account and loads the latest server state. Changes sync across devices; use version numbers/ETags or equivalent optimistic concurrency to prevent overwrites.
- Keep an encrypted local cache for resilience/offline viewing, but never treat it as authoritative. On reconnect, reconcile with the server.
- Long-running jobs execute in server-side workers/agents, not in the foreground phone process. A phone can disconnect, power off, or be replaced without losing progress.
- Provide explicit last-synced time, active task status, and a safe resume action. Do not silently replay non-idempotent actions.

## BARQ Brain — assistant capabilities
1. Consultation: understand questions, explain architecture, diagnose issues, compare options, and propose plans.
2. Engineering execution: inspect repository and history, edit code, create branches/commits/PRs, run tests, inspect logs, and prepare releases.
3. Administration: authorized user, group, report, block, and support operations with audit trails.
4. Project-wide knowledge: maintain a searchable, versioned project knowledge index over source code, API contracts, schema/migrations, test suites, deployment configuration, product requirements, and owner-approved decisions. Refresh it after relevant commits and changes.
5. Task continuity: summarize what was done, why, evidence/results, unresolved issues, and the exact next action. Resume from durable checkpoints rather than relying on chat context alone.

## Security and owner control
- Strong authentication; short-lived access tokens and revocable device sessions.
- Server-side role-based access control and least privilege. Owner, administrator, support, and read-only roles must be distinct.
- Require explicit owner approval for destructive data changes, account bans at scale, production deployments, schema migrations, secret rotation, and other high-impact actions.
- Show a human-readable action preview (target, scope, impact, environment) before approval.
- Keep immutable audit events: actor, device/session, action, target, timestamp, approval, outcome, and correlation/task ID. Never log passwords, tokens, or secret values.
- Store secrets only in a managed server-side secret store; never embed them in the APK or sync them to device storage.
- Separate preview/staging from production. Default all engineering tests to isolated preview resources.

## Suggested architecture (implementation proposal)
- Android client: Flutter, compatible with Android 8 / API 26; adaptive UI and accessible controls.
- Admin API: authenticated service with versioned endpoints for workspace, tasks, assistant sessions, approvals, audit, users, groups, and support tools.
- Durable database: relational storage for accounts, devices, workspaces, tasks, checkpoints, approvals, and audit events.
- Object storage: encrypted artifacts, logs, exports, and generated reports.
- Job runner: durable queue + workers for repository operations, builds, tests, deployments, and long-running investigations.
- Knowledge service: repository ingestion, document/code chunking, metadata/version tracking, and retrieval with citations to exact files/commits.
- Assistant orchestration: tool permissions scoped by role and environment; every tool call recorded against a task and approval policy.
- Push notifications: job completion, approval requests, failures, and security alerts. Push is a notification channel, not the persistence mechanism.

## Core screens
- Overview: project health, current phase, active tasks, recent failures, and last sync.
- BARQ Brain: conversational assistant with visible mode and execution state.
- Project map: app, API, database, workers, integrations, CI, environments, and dependencies.
- Tasks and checkpoints: resumable task timeline and next action.
- Users and groups: search, account status, reports, moderation, and support actions.
- Approvals: pending action previews with approve/reject and audit history.
- Activity/audit: searchable timeline with filters.
- Devices and security: active sessions, revoke device, role and permission visibility.

## Delivery sequence
A. Finalize requirements, threat model, and screen flows.
B. Define admin API contracts, database schema, RBAC matrix, and durable task state machine.
C. Build a read-only project overview and assistant consultation mode.
D. Add repository knowledge ingestion and cited project answers.
E. Add preview-only engineering execution with resumable jobs.
F. Add owner-approved production operations and user/group administration.
G. Test device replacement, concurrent sessions, offline/reconnect, recovery, and permission boundaries.

## Acceptance tests for phone-to-phone continuation
1. Start a task on phone A and persist a checkpoint.
2. Sign in on phone B; see the same workspace, conversation, task, and checkpoint.
3. Resume on phone B and complete the next step; phone A reflects the updated state after sync.
4. Kill/uninstall the app on phone A during a server-side job; the job continues and can be monitored from phone B.
5. Simulate network loss and concurrent edits; no acknowledged server checkpoint is lost or silently overwritten.
6. Revoke phone A; it can no longer access workspace data or execute actions.
7. Verify that no API keys or secrets are stored in APK assets, logs, or client-side persistent storage.

## Scope boundary
This is the agreed planning baseline. It does not mean BARQ Admin has been implemented or connected to production. BARQ Android APK delivery remains the immediate priority; admin implementation must not block it.

## Always-on execution while the owner is offline
- The owner's phone is a control and monitoring client, not the execution host. Closing the app, disconnecting mobile data/Wi-Fi, or switching devices must not stop an accepted server-side task.
- Every long-running task is submitted to a durable server queue and claimed by a worker with a renewable lease/heartbeat. A worker crash or deployment restarts the task from the latest committed checkpoint.
- Persist each step's input reference, output reference, status, timestamps, retry count, idempotency key, and checkpoint before acknowledging progress.
- Use bounded retries for transient failures; pause for owner input or approval when needed. Never repeat a payment, public post, destructive action, or production mutation without idempotency protection and the required approval.
- The app shows queued/running/paused/needs-approval/failed/completed states, last checkpoint, next action, and last server sync. Push notifications are optional alerts; work continues without push delivery.
- Provide owner controls to pause, resume, cancel, inspect logs, and revoke a worker's authority. Cancellation must be cooperative and report any irreversible step already completed.

## BARQ launch and growth companion
BARQ Brain includes a dedicated launch-and-growth workspace to help the owner take BARQ from testing through global release and sustainable growth:
- Build and maintain a staged go-to-market plan for launch readiness, beta testing, country/language expansion, app-store listing, launch campaigns, and post-launch retention.
- Research target audiences, markets, competitor positioning, localization needs, store policies, and channel opportunities; attach sources and dates to market claims.
- Draft Arabic and English store descriptions, landing-page copy, social posts, short-video scripts, press kits, creator outreach, community announcements, and support responses in BARQ's approved brand voice.
- Plan campaigns and budgets, define measurable goals (installs, activation, retention, referrals only if later approved, and support quality), and report results from connected analytics sources when authorized.
- Maintain a content calendar, campaign/task checkpoints, creative versions, approval history, and lessons learned centrally so work can continue from any device.
- Recommend experiments and explain expected cost, reach, risk, and success metrics. Distinguish verified results from estimates and assumptions.
- Do not publish posts, contact creators, buy ads, spend money, change store listings, or make public product claims without explicit owner approval. Never promise rankings or guaranteed virality; optimize ethically for user value, trust, safety, and retention.

## Additional acceptance tests: offline work and growth operations
8. Submit a long-running task, disconnect every owner device, and verify the server worker continues to the next durable checkpoint.
9. Restart a worker mid-task and verify recovery from the last committed checkpoint without duplicate side effects.
10. Reconnect from a different phone and verify current status, logs, outputs, approvals, and next action are synchronized.
11. Draft a launch campaign while offline from the phone cache; queue the draft safely and reconcile it on reconnect without overwriting newer server data.
12. Require owner approval before any external publication, paid promotion, creator outreach, or store-listing change.

