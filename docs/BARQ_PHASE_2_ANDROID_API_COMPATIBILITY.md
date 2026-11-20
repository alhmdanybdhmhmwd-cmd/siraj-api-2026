# BARQ Phase 2 — Android/API route compatibility review

Review basis:
- Android source snapshot: `BARQ_PHASE_2_ANDROID_SOURCE_VALIDATED.zip`, `lib/main.dart`.
- Worker source: `src/src/index.js` on `barq/phase-2-d1-isolated-2026-11-20`.
- This is a static route-presence comparison, not a live integration test. It does not validate request/response field compatibility or authentication behavior.

## Confirmed route presence in the Worker

The Worker contains route handlers for:
- `POST /api/login`
- `POST /api/register`
- `POST /api/password/recover`
- `POST /api/recovery-code`
- `GET /api/me`
- `POST /api/profile`
- `GET|POST /api/privacy`
- `GET|POST /api/notification-settings`
- `GET|POST|DELETE /api/devices/token` (method support is route-specific)
- `GET|POST /api/statuses`
- `GET /api/users/search`
- `POST /api/contacts` and `POST /api/contacts/match`
- `GET /api/friends`
- `GET|POST /api/messages`
- `GET|POST /api/groups` and nested group routes
- `GET /health/live` and `GET /health/ready`

## Gaps requiring follow-up before claiming full Android/API integration

1. **Ephemeral messages:** Android calls `GET|POST /api/ephemeral-messages`; no matching handler exists in this Worker source revision. Do not present ephemeral messaging as server-integrated on this revision.
2. **Referral link:** Android calls `GET /api/referrals`; no matching handler was found in this Worker source revision. Keep the product requirement to a private invite link only; do not add referral counts, badges, rewards, or friend thresholds.
3. **Profile photo:** the Android profile update method currently sends display name and phone only. This review found no corresponding Android profile-photo upload method in that API client. Profile image upload/display remains unverified.

## Safety and verification limits

- Do not point test or migration commands at the production D1 database.
- The isolated D1 database and local Worker health probes were validated separately.
- No production Worker deployment, production DB migration, PR merge, or live-device test was performed by this review.
- A real Flutter analyze/test/build and two-device Android test remain outstanding because Flutter/Dart tooling is unavailable in the current execution environment.

## Next engineering action

Resolve the two missing route contracts (ephemeral messaging and private invite-link retrieval) in a reviewed, isolated change, then add automated contract tests that compare the Android client expectations with the Worker handlers. Keep profile-photo upload as a separately tracked integration gap.
