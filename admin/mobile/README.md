# BARQ Admin Mobile

Arabic RTL Flutter client for the independent BARQ Admin owner workspace.

## Current capabilities

- Dark electric-blue and gold visual system, dashboard, tasks, owner approvals, and read-only audit timeline.
- Server-issued activation code for trusted devices; the same code can activate multiple phones.
- A visible, authenticated activation-code panel with copy action for the owner.
- A per-device 6–12 digit local PIN gate on first activation and whenever the app returns to the foreground; only a salted PBKDF2-HMAC-SHA256 verifier is stored in Android secure storage.
- A 10-minute Admin access token plus a rotating 30-day refresh token stored in Android secure storage.
- Automatic access-token refresh, server-side logout, owner device inventory, and device/session revocation.
- Cached workspace snapshots and a local offline task outbox.
- Refresh/resume synchronization with the Admin API.
- Android APK generation is deliberately deferred until programming, integration, and acceptance tests are complete.

## Stable Android release signing (private)

The Admin release APK must use one persistent signing key so future updates can replace the installed app cleanly. Never commit the keystore or paste its password/private material into chat.

Generate the keystore once on a trusted computer (keep a secure offline backup):

```sh
keytool -genkeypair -v -keystore barq-admin-release.jks -alias barq-admin -keyalg RSA -keysize 2048 -validity 10000
keytool -list -v -keystore barq-admin-release.jks -alias barq-admin
base64 -w0 barq-admin-release.jks
```

Store the Base64 output and the three credentials as GitHub Actions repository **Secrets** (not Variables):
- `BARQ_ADMIN_KEYSTORE_BASE64`
- `BARQ_ADMIN_KEYSTORE_PASSWORD`
- `BARQ_ADMIN_KEY_ALIAS` (use `barq-admin`)
- `BARQ_ADMIN_KEY_PASSWORD`

The workflow decodes the keystore only on the temporary runner and signs the ARM64 release APK with that same key. Do not rotate or regenerate the signing key; losing it means future updates cannot replace the installed app cleanly.

## Activation code and server configuration

The mobile app does not contain the activation secret. Configure a high-entropy random value (at least 32 characters) as the Cloudflare Worker secret `BARQ_ADMIN_ACTIVATION_CODE`, and configure `BARQ_ADMIN_JWT_SECRET` as a separate server-only secret of at least 32 characters. Never commit either value, place either in GitHub Variables, print either in logs, or embed either in the APK.

The activation endpoint rate-limits attempts by client IP and a fingerprint of the supplied code. A successful activation creates a distinct revocable device session; the same master code may be used on multiple trusted devices. After activation, each device must create its own local PIN. The app locks again when it returns to the foreground. The PIN is never stored as plain text; a salted PBKDF2-HMAC-SHA256 verifier is stored through Android secure storage. Once unlocked, the app shows the activation code in its **رمز التفعيل** section so the owner can copy it. Anyone with an active owner session on a trusted device can view that code, as explicitly requested by the owner. Rotate the Worker secret to invalidate the old code and issue a new one. Device sessions remain individually revocable from the device-management screen.

The shared BARQ Worker runtime and its existing D1 binding are reused. Activation sessions use the stable owner subject `barq-admin-owner-v1`; all Admin-owned tables retain their `admin_` namespace. No production database migration is required for this activation flow because it reuses the existing device, session, refresh-history, and rate-limit tables. Do not change the BARQ consumer app or its working API configuration.

The Cloudflare Worker secret must be provisioned separately in the correct Preview environment before activation can succeed. This repository workflow does not create or reveal Cloudflare secrets. Do not send the secret through chat or commit it to GitHub.

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

The shared-runtime handler reuses BARQ's existing Worker and D1 binding while keeping owner authentication and all Admin-owned tables separate. The Admin Queue is still optional and must be provisioned separately if durable background task execution is enabled; without it, accepted tasks remain persisted but wait for queue execution. Never reuse consumer-user sessions. The current BARQ Brain worker creates server-side assistant drafts; it does not autonomously edit BARQ source code or deploy.

## Owner operating agreement

BARQ is the main product, SPARK is its stories feature, BARQ Admin is the separate management app, and BARQ Brain is its assistant. The owner explicitly authorized Phase 2 on 2026-11-24. BARQ Brain project understanding and repository/code indexing are in progress; do not claim complete coverage until real Preview indexing and coverage/freshness checks pass. Production publishing, deployment, merging, pull-request base changes, spending, and other consequential external actions require specific owner approval.


## Owner activation code management

After the first trusted owner session is established, the owner can view, copy, generate, replace, or disable the BARQ Admin activation code from inside the app. The Worker stores only a SHA-256 verifier and AES-GCM ciphertext in the isolated Admin database; the encryption key is derived from the server-only `BARQ_ADMIN_JWT_SECRET`. Replacing the code blocks new activations using the previous code. Existing device sessions remain independent and can be revoked from the device manager. Disabling the activation code blocks new device activations without silently signing out existing devices.

The initial owner bootstrap still requires a trusted server-side bootstrap credential to exist before the first owner session. Do not expose a public first-owner setup endpoint or embed a bootstrap secret in the APK. The activation-management migration is `0008_activation_code_management.sql`; apply it only to the isolated Admin Preview database for testing. Do not apply it to a shared/production BARQ database without explicit owner approval.
