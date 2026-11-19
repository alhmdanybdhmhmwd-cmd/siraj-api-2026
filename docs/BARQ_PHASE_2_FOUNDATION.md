# BARQ Phase 2 — Application Foundation and API Security

Status: IN PROGRESS
Working branch: barq/phase-2-foundation-2026-11-20
Base branch: barq/development-2026-11-19

## Scope
This phase establishes a safe development foundation and verifies the existing authentication/session contract. It does not authorize production deployment, database migrations against production, merging, or release.

## Confirmed source facts
- Android package namespace and applicationId are both `com.barq.app`.
- The checked-in Firebase Android configuration uses package name `com.barq.app`.
- Flutter REST traffic currently targets `https://siraj-api-2026.vercel.app`.
- Large-media fallback and the realtime WebSocket target `siraj-api.alhmdanybdhmhmwd.workers.dev`.
- Flutter stores the bearer token with `flutter_secure_storage`; it validates a saved token with `GET /api/me` at startup.
- The Worker issues HS256 JWTs with a 30-day expiry and a session-version claim (`sv`).
- The Worker checks the JWT signature, expiry, and current account session version on authenticated requests.
- Password recovery increments the account session version, invalidating prior tokens.
- Login and registration have rate-limit checks; registration validates password length (8–128 chars) and uses PBKDF2-HMAC-SHA256 with 100,000 iterations.
- Android release signing currently points to the debug signing configuration and is not production-ready.

## Blocking safety findings
1. The Wrangler development branch currently binds `DB` to the same D1 database ID as the production configuration. No schema change, migration, destructive test, or deployment is permitted until a separate preview D1 database is provisioned and its ID is independently verified.
2. The Android source hardcodes the production Vercel API origin. A separate preview API origin and build-time environment selection are needed before end-to-end development tests can safely use non-production accounts.
3. The app and Worker use different origins for REST, media, and realtime. Their route ownership, authentication behavior, and deployment mapping must be verified before changing endpoints.
4. The Worker token model has account-level session-version invalidation, but the reviewed route set does not establish a per-device logout/revocation contract. Do not add a logout route that revokes every device without deciding and testing the intended semantics.
5. Flutter tooling is not installed in the current execution environment. Flutter analyze, unit tests, Android build, and device tests remain unverified here.
6. Release signing must be configured using a user-controlled keystore in a secure environment. Never commit keystore files or passwords.

## Phase 2 completion criteria
- A separately provisioned preview D1 database is configured and verified not to equal the production database ID.
- A preview API deployment/origin is established and Android can select it without changing production defaults.
- Authentication contract tests cover registration, login by username/phone, expired/invalid tokens, recovery-code single use, session invalidation, and rate limiting.
- Token persistence, offline startup behavior, and logout semantics are explicitly tested.
- The Android package ID and Firebase configuration are verified together; no package rename is made without migration planning.
- No secrets are embedded in the APK or repository.
- Flutter analyze/tests and an Android debug build pass in a capable Flutter environment.

## Product decisions retained
- The invite feature is a private invite link only.
- No “Lightning” badge, no five-friends threshold, and no gold frame.
- The six-feature list must not reintroduce the removed badge/reward condition.
- The user must explicitly approve completion of each phase before work starts on the next phase.

## Safety boundary
Until the preview D1 database and preview API are available, work is limited to source review, isolated branch changes, local/static tests, and documentation. Do not point development traffic at production data.

## Implemented on the isolated phase branch
- Added `GET /health/live`, which reports Worker liveness without requiring D1 or secrets.
- Added `GET /health/ready`, which checks required configuration and executes only `SELECT 1 AS ok` against the configured D1 binding. It returns HTTP 503 when configuration or the read-only probe is unavailable.
- These probes do not create tables, write rows, or run migrations.
- The changes are source-only and have not been deployed. Runtime verification remains pending until an isolated preview environment is available.

## Additional client foundation work

- Android source snapshot: API, media, and realtime origins now support build-time `--dart-define` values (`BARQ_API_BASE`, `BARQ_MEDIA_BASE`, `BARQ_REALTIME_URL`) while retaining production defaults. This source snapshot is packaged separately because the Android project is not part of this GitHub repository.
- Flutter compilation and tests have not yet been run; this environment does not currently provide Flutter/Dart tooling.

## Remaining work before phase completion
- Provision and verify a distinct preview D1 database ID; the current Wrangler binding still points at the production database.
- Establish a preview Worker/API URL and supply the verified values to the Android build-time environment selectors.
- Added isolated Node tests for `/health/live` and `/health/ready`, including missing configuration, successful read-only `SELECT 1`, and database failure paths (`test/health.test.mjs`). These tests are committed but have not yet been executed in CI or locally.
- Run the repository test workflow and Flutter analyze/tests/build in a suitable toolchain.
- Verify API, media, and realtime origin routing and the Android package/Firebase identity.
