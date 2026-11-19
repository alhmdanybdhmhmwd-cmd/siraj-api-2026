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

## Confirmed gaps and work status
1. **Recovery code — implemented on this development branch (not deployed):** registration now returns a cryptographically random one-time recovery code; the backend stores only a salted PBKDF2 hash; `POST /api/password/recover` validates username/phone plus code, updates the password, and consumes the code; authenticated `POST /api/recovery-code` rotates it after current-password verification. Existing users without a code can use the rotate endpoint after signing in.
2. **Realtime:** the Flutter client contains a WebSocket client for `/api/realtime`, but the current Worker does not implement a WebSocket upgrade or realtime route. Polling is the current fallback; realtime is still open.
3. **Direct contacts:** `/api/contacts` already exists in the Worker and adds both sides directly. Legacy friend-request routes remain in the backend for compatibility, but must not be exposed or required by the product flow.
4. **Automatic phone-contact matching/synchronization** is not present in the inspected client API surface. Implement only with explicit contacts permission and privacy-safe matching.
5. **End-to-end encryption** was not found in the inspected Flutter dependency list or Worker source.
6. **Six approved features** remain unimplemented in the inspected source: Lightning mode, nearby offline messaging and later sync, read-triggered 10-second ephemeral messages excluded from Firebase, Arabic-English live translation, voice transcription, and invite rewards (five verified registrations => "صاعقة" title and gold avatar frame).
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
