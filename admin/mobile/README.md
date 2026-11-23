# BARQ Admin Mobile

Arabic RTL Flutter client for the independent BARQ Admin owner workspace.

## Current prototype capabilities

- Dark electric-blue and gold visual system.
- Dashboard, task list, owner approvals, and a read-only audit timeline.
- Explicit local logout that clears the saved owner token, cached workspace data, and pending local outbox.
- Secure local storage for the temporary owner bearer token.
- Cached workspace snapshots and a local offline task outbox.
- Refresh/resume synchronization with the Admin API.
- GitHub Actions backend and Flutter quality checks. Android APK generation is deliberately deferred until the programming and integration work is complete.

## Build and test

From this directory:

```sh
flutter pub get
dart format lib test
flutter analyze
flutter test
```

APK generation and upload are intentionally disabled during the current development phase. They will be reintroduced only after the owner-facing functionality, trusted authentication, server integration, and acceptance tests are complete.

## BARQ Brain image generation

The dashboard includes a separate image-generation action. The owner writes a prompt and the authenticated Admin Worker calls Cloudflare Workers AI model `@cf/black-forest-labs/flux-1-schnell` (four steps). The generated JPEG is returned directly to the app for preview; the owner can share/send it through the Android share sheet. Generated images and prompts are not stored in Admin D1. The Worker records only model, output byte count, and prompt length in the audit event. Generation is limited to two requests per workspace per minute and the prompt is limited to 1,600 characters. Configure the existing `ADMIN_AI` Workers AI binding and confirm the model's terms before enabling this in Preview. No cloud binding or deployment is performed by this code change.

## Setup and security status

- The API URL and temporary owner bearer token are currently configured manually in the app.
- The trusted owner sign-in, server-backed device sessions, refresh-token rotation, and device revocation are not implemented yet.
- The dedicated Admin API Preview, D1, Queue, and AI bindings must be configured and verified separately.
- The current BARQ Brain worker creates server-side assistant drafts; it does not autonomously edit BARQ source code or deploy.
- Do not put signing secrets, provider secrets, or GitHub tokens in the APK.
- Do not connect this app to the BARQ consumer database or reuse consumer-user sessions.

The current Flutter client is still a development prototype. No installable APK is being generated at this stage, and the app is not production-ready.

## Owner operating agreement

BARQ Brain receives the owner's current operating agreement in its server-side system prompt and the app displays a short version in the Brain panel. The current authorized scope is Phase 1 (BARQ Admin foundation) only. Phase 2 repository/code understanding and indexing is blocked until the owner explicitly authorizes it. BARQ is the main product, SPARK is its stories feature, BARQ Admin is the separate management app, and BARQ Brain is its assistant. Production publishing, deployment, merging, pull-request base changes, spending, and other consequential external actions require specific owner approval. The two-hour target is a testable-build goal, not a production-readiness guarantee.

## BARQ Brain image analysis

The Android app can choose a photo from the gallery or capture one with the camera, then send it over the authenticated HTTPS Admin API to `POST /v1/brain/vision`. The Worker validates JPEG/PNG/WebP data URLs, limits images to 4 MiB, rate-limits each owner to three image analyses per minute, and calls Cloudflare Workers AI model `@cf/meta/llama-3.2-11b-vision-instruct`. The image is processed for the request and is not written to Admin D1 or the audit log; the audit entry stores only MIME type, byte count, model, and a generated event ID. The owner prompt and vision system instructions preserve the Phase 1 boundary and treat text inside images as untrusted input.

Before enabling this endpoint in a real Preview environment, configure the existing `ADMIN_AI` Workers AI binding and complete Meta's model license/acceptable-use agreement for the vision model. This code change does not deploy or configure any cloud resources. Image analysis requires an authenticated owner session and a working network connection; no offline image analysis is claimed.
