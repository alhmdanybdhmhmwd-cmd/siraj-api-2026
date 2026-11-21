# BARQ media upload and retention policy — 2026-11-19

## Upload size
- The Cloudflare Worker accepts media objects up to 60 MiB (62,914,560 bytes).
- The Vercel proxy has matching application-level checks, but Vercel Functions impose a hard 4.5 MB request-body limit. A 60 MiB upload must therefore be sent directly from the Android client to the Worker media endpoint, not through the Vercel Function proxy.
- Android routing to the direct Worker media endpoint is still a client integration task and must be completed in the Android integration stage. Do not claim 60 MiB uploads work end-to-end until that is tested.

## Per-object retention
- Every newly uploaded object receives its own UTC expiration timestamp, exactly 72 hours after upload begins.
- The timestamp is stored as Tigris object metadata and in the lazy-created D1 table `media_expirations`, keyed by the unique object key.
- A Worker Cron Trigger runs every 15 minutes and deletes only rows whose individual `expires_at` has passed. It deletes the corresponding object and then its own tracking row. Failed storage deletes remain queued for retry.
- Media GET also checks the object's own expiration metadata and refuses expired objects (HTTP 410), attempting immediate deletion. This closes the gap until the next scheduled cleanup.
- A later attachment has a later expiration timestamp and is not affected when an earlier attachment expires.
- Existing objects without an expiration record/metadata are not bulk-deleted by this change.

## Safety and verification
- The expiration table is additive and created lazily; no production D1 migration is applied.
- Cleanup processes at most 100 expired objects per scheduled invocation to bound work; remaining expired objects are handled by subsequent runs.
- Unit tests cover independent object expiry, cleanup isolation, and the 15-minute cron configuration.
- Tigris and D1 live integration, Cron execution in a non-production preview, and the Android direct-upload path remain to be verified before release.
