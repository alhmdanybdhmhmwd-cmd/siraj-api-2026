# BARQ Admin Mobile

Arabic RTL Flutter client for the independent BARQ Admin owner workspace.

## Current prototype capabilities

- Dark electric-blue and gold visual system.
- Dashboard, task list, owner approvals, and a read-only audit timeline.
- Explicit local logout that clears the saved owner token, cached workspace data, and pending local outbox.
- Secure local storage for the temporary owner bearer token.
- Cached workspace snapshots and a local offline task outbox.
- Refresh/resume synchronization with the Admin API.
- GitHub Actions quality checks and an installable Android **debug APK** artifact.

## Build and test

From this directory:

```sh
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter create --platforms=android --org com.barq .
flutter build apk --debug
```

The CI workflow uploads `app-debug.apk` as the `barq-admin-debug-apk` artifact for seven days after a successful build. This is a debug/testing artifact, not a signed production release.

## Setup and security status

- The API URL and temporary owner bearer token are currently configured manually in the app.
- The trusted owner sign-in, server-backed device sessions, refresh-token rotation, and device revocation are not implemented yet.
- The dedicated Admin API Preview, D1, Queue, and AI bindings must be configured and verified separately.
- The current BARQ Brain worker creates server-side assistant drafts; it does not autonomously edit BARQ source code or deploy.
- Do not put signing secrets, provider secrets, or GitHub tokens in the APK.
- Do not connect this app to the BARQ consumer database or reuse consumer-user sessions.

This build is suitable for internal UI and integration testing only. It is not production-ready.

## Owner operating agreement

BARQ Brain receives the owner's current operating agreement in its server-side system prompt and the app displays a short version in the Brain panel. The current authorized scope is Phase 1 (BARQ Admin foundation) only. Phase 2 repository/code understanding and indexing is blocked until the owner explicitly authorizes it. BARQ is the main product, SPARK is its stories feature, BARQ Admin is the separate management app, and BARQ Brain is its assistant. Production publishing, deployment, merging, pull-request base changes, spending, and other consequential external actions require specific owner approval. The two-hour target is a testable-build goal, not a production-readiness guarantee.
