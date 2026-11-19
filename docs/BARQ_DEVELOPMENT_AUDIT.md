# BARQ Development Audit — 2026-11-19

This branch is a safe development workspace. Production `main` is unchanged.

## Source baseline
- Android Flutter source: `barq-android/lib/main.dart` from the supplied BARQ source archive.
- API repository: `alhmdanybdhmhmwd-cmd/siraj-api-2026`.
- Existing app API base: `https://siraj-api-2026.vercel.app`.
- Existing app realtime URL: `wss://siraj-api.alhmdanybdhmhmwd.workers.dev/api/realtime`.
- Android application ID and Firebase client identity must remain compatible with the existing installation.

## Existing work to preserve and finish
- Authentication by username or phone and password.
- Recovery-code generation, rotation, one-time password recovery, and session invalidation are implemented on the development branch; end-to-end verification remains open.
- Direct contact adding without friend requests.
- Friends, private messages, groups, statuses, file attachments.
- Privacy settings, notification preferences, FCM device-token registration.
- Profile editing, logout, Arabic RTL interface and existing visual identity.
- Existing API compatibility, stored credentials and user data.

## Old work status (new six features are explicitly deferred)
1. **Recovery code:** implemented on this development branch (not deployed). Registration returns a cryptographically random one-time code; only a salted PBKDF2 hash is stored; password recovery consumes the matching code; users can rotate the code after signing in and verifying their current password.
2. **Session invalidation:** implemented on this development branch. JWTs carry a per-account session version; successful password recovery increments it atomically with the password update and code consumption, rejecting previously issued sessions.
3. **Recovery tests:** added Node built-in tests for session-version invalidation, password update, one-time code consumption, and rejection of reuse. Added a CI workflow to run these tests and Worker syntax validation. The workflow result must be confirmed before calling tests passed.
4. **Media proxy:** fixed `api/[...path].js` on this branch to forward `X-File-Name`, `X-Recipient-Id`, and `X-Group-Id`, and preserve `Content-Disposition` / cache headers. The Vercel preview deployment for commit `e27aa895` reached READY; its preview API root returned HTTP 200 and advertised the expected CORS headers. This does not test authenticated media upload/download yet.
5. **Realtime:** the Flutter client currently uses REST polling through Vercel every five seconds. The Cloudflare Worker does not implement a WebSocket upgrade. Reliable realtime remains open; do not route the app to workers.dev until the route and network compatibility are proven.
6. **Phone contacts:** the backend `POST /api/contacts/match` endpoint is implemented on this branch. It accepts at most 500 phone values, normalizes Yemen/international formats in memory, respects each account's searchable privacy setting, and does not persist the submitted contact list. The working Flutter source snapshot now includes explicit READ_CONTACTS permission, opt-in matching, direct-add controls, and automatic re-sync on app resume/contact-book change. Flutter analysis and Android device verification are still pending.
7. **End-to-end encryption:** not implemented in the inspected source.
8. **Release verification:** still needs a Cloudflare preview environment that uses a separate non-production database, Flutter/API contract checks, two-device tests for registration, recovery, direct messaging, read receipts, groups, media, push notifications and reconnect/sync, plus network tests on Yemen Net, Yemen Mobile, Sabafon and another network without VPN.
9. **Android source:** the available ZIP is the 18-Nov source snapshot; a working copy includes phone-contact sync, a corrected Flutter smoke test, lifecycle-aware polling, and adaptive retry backoff. The APK workflow in that working copy has been changed to manual validation only; release APK generation is disabled. Preserve package ID `com.siraj.app.siraj`, Firebase client identity, secure-storage keys, API URL, and all existing features. Flutter SDK is not available in this work environment, so Android analysis/build has not been run.

**Deferred by explicit user instruction:** do not start the six approved new features until all items above that apply to the existing product are completed and tested.
## Implementation order
1. Reconcile the complete existing requirements and finish old in-progress work first, especially recovery-code/password recovery, API/realtime consistency, contact matching, and reliable message delivery.
2. Add the six approved features in independently testable increments.
3. Preserve Android 8+ support, current package/Firebase identity, existing user data and all working features.
4. Test API contracts, migrations, security, reconnect/sync, and device behavior before any release APK.

## Safety constraints
- Work on this branch; do not make unreviewed production changes.
- Do not change production API URLs, package ID, Firebase project/client identity, auth token storage keys, or database records casually.
- Never claim a feature is implemented until code and tests verify it.
- Do not produce a final release APK until all requirements and tests are complete.
- The connectivity-without-VPN issue on the other phone remains an open BARQ test item; unrelated legacy Siraj search/connectivity issues must not be misclassified as BARQ defects.
