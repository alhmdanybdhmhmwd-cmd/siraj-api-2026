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
- Recovery-code generation and password recovery (client methods exist; server route/response parity must be completed and tested).
- Direct contact adding without friend requests.
- Friends, private messages, groups, statuses, file attachments.
- Privacy settings, notification preferences, FCM device-token registration.
- Profile editing, logout, Arabic RTL interface and existing visual identity.
- Existing API compatibility, stored credentials and user data.

## Old work status (new six features are explicitly deferred)
1. **Recovery code:** implemented on this development branch (not deployed). Registration returns a cryptographically random one-time code; only a salted PBKDF2 hash is stored; password recovery consumes the matching code; users can rotate the code after signing in and verifying their current password.
2. **Session invalidation:** implemented on this development branch. JWTs carry a per-account session version; successful password recovery increments it atomically with the password update and code consumption, rejecting previously issued sessions.
3. **Recovery tests:** added Node built-in tests for session-version invalidation, password update, one-time code consumption, and rejection of reuse. Added a CI workflow to run these tests and Worker syntax validation. The workflow result must be confirmed before calling tests passed.
4. **Media proxy:** fixed `api/[...path].js` on this branch to forward `X-File-Name`, `X-Recipient-Id`, and `X-Group-Id`, and preserve `Content-Disposition` / cache headers. The Vercel status check for this commit reported success.
5. **Realtime:** the Flutter client currently uses REST polling through Vercel every five seconds. The Cloudflare Worker does not implement a WebSocket upgrade. Reliable realtime remains open; do not route the app to workers.dev until the route and network compatibility are proven.
6. **Phone contacts:** automatic permission-based phone contact matching and synchronization are not implemented in the available Flutter source. The existing `POST /api/contacts` endpoint adds a selected person directly, without requiring a friend request.
7. **End-to-end encryption:** not implemented in the inspected source.
8. **Release verification:** still needs a Cloudflare preview environment that uses a separate non-production database, Flutter/API contract checks, two-device tests for registration, recovery, direct messaging, read receipts, groups, media, push notifications and reconnect/sync, plus network tests on Yemen Net, Yemen Mobile, Sabafon and another network without VPN.
9. **Android source:** the available ZIP is the 18-Nov source snapshot. Preserve its package ID `com.siraj.app.siraj`, Firebase client identity, secure-storage keys, API URL, and all existing features. Flutter SDK was not available in this work environment, so Android analysis/build has not been run.

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
