# BARQ Admin Mobile

Arabic RTL Flutter client for the independent BARQ Admin owner workspace.

## Current capabilities

- Dark electric-blue and gold visual system, dashboard, tasks, owner approvals, and read-only audit timeline.
- Google OpenID Connect sign-in through native AppAuth using Authorization Code + PKCE; no password or provider client secret is stored in the app.
- A 10-minute Admin access token plus a rotating 30-day refresh token stored in Android secure storage.
- Automatic access-token refresh, server-side logout, owner device inventory, and device/session revocation.
- Cached workspace snapshots and a local offline task outbox.
- Refresh/resume synchronization with the Admin API.
- Android APK generation is deliberately deferred until programming, integration, and acceptance tests are complete.

## Google OAuth configuration

1. Create a Google OAuth client for the native Android application in Google Cloud Console. Register the exact Android package name and signing-certificate SHA-1 fingerprint used by the eventual build.
2. Configure the matching Google native redirect scheme for AppAuth. The app derives the callback as `com.googleusercontent.apps.<client-id-prefix>:/oauth2redirect`; the Android manifest must register that scheme before a device build.
3. Build the client with the public client identifier:
   `--dart-define=BARQ_GOOGLE_OIDC_CLIENT_ID=<Google-native-client-id>`.
4. Configure the dedicated Admin Preview Worker variables/secrets:
   - `BARQ_GOOGLE_OIDC_CLIENT_ID`: the same public Google client ID.
   - `BARQ_ADMIN_OWNER_EMAIL`: the exact Google account email permitted to own this Admin workspace. Google must mark it verified.
   - `BARQ_ADMIN_JWT_SECRET`: a random server-only secret of at least 32 characters.
   - `BARQ_ADMIN_ALLOWED_ORIGIN`: the exact app/web origin where applicable.
   - Optional `BARQ_ADMIN_OWNER_SUBJECT`: pin the verified Google `sub` after first controlled enrollment.
5. Provision the dedicated Admin Preview D1 database and both queues (`barq-admin-preview-tasks` and `barq-admin-preview-dlq`) using the instructions in `admin/README.md` and `admin/wrangler.toml.example`. From the `admin/` directory, apply all pending Admin migrations in order with `npx wrangler d1 migrations apply barq-admin-preview --remote`; do not manually apply only migration 0005, and never target BARQ consumer production data.

The Worker validates Google RS256 signatures using Google's published signing keys and checks issuer, audience, expiry, verified email, owner allowlist, and one-time OIDC nonce. The Worker then issues its own session tokens. Google access tokens are not used as Admin API bearer tokens. The opaque refresh token is stored server-side only as a SHA-256 hash and rotated on every refresh; reuse revokes that session. Each API request checks that its session and device are still active. No signing secret belongs in the APK.

The app currently allows the owner to configure the HTTPS Admin API base URL from Settings. Google login remains disabled until the public client ID is supplied at build time and the matching server Preview configuration is installed.

## Build and test

From this directory:

```sh
flutter pub get
dart format lib test
flutter analyze
flutter test
```

APK generation and upload remain disabled until the owner-facing functionality, trusted authentication, server integration, and acceptance tests are complete.

## BARQ Brain image generation

The dashboard includes a separate image-generation action. The owner writes a prompt and the authenticated Admin Worker calls Cloudflare Workers AI model `@cf/black-forest-labs/flux-1-schnell` (four steps). The generated JPEG is returned directly to the app for preview; the owner can share/send it through the Android share sheet. Generated images and prompts are not stored in Admin D1. The Worker records only model, output byte count, and prompt length in the audit event. The application imposes no daily, per-minute, or lifetime request-count quota on image generation; the prompt remains limited to 1,600 characters and requests remain subject to provider availability, account-level service limits, and technical payload validation. Configure the existing `ADMIN_AI` Workers AI binding and confirm the model's terms before enabling this in Preview.

## BARQ Brain image analysis

The Android app can choose a photo from the gallery or capture one with the camera, then send it over the authenticated HTTPS Admin API to `POST /v1/brain/vision`. The Worker validates JPEG/PNG/WebP data URLs, limits each image payload to 4 MiB, and calls Cloudflare Workers AI model `@cf/meta/llama-3.2-11b-vision-instruct`. The application imposes no daily, per-minute, or lifetime request-count quota on image analysis; requests remain subject to provider availability and account-level service limits. The image is processed for the request and is not written to Admin D1 or the audit log; the audit entry stores only MIME type, byte count, model, and a generated event ID. Text inside images is treated as untrusted input.

The dedicated Admin Preview D1, Queue, and AI bindings must be configured and verified separately. The current BARQ Brain worker creates server-side assistant drafts; it does not autonomously edit BARQ source code or deploy. Do not connect this app to the BARQ consumer database or reuse consumer-user sessions.

## Owner operating agreement

BARQ is the main product, SPARK is its stories feature, BARQ Admin is the separate management app, and BARQ Brain is its assistant. The current authorized scope is Phase 1 only. Phase 2 repository/code understanding and indexing is blocked until the owner explicitly authorizes it. Production publishing, deployment, merging, pull-request base changes, spending, and other consequential external actions require specific owner approval.
