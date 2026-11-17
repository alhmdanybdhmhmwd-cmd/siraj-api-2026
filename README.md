# Siraj API

Cloudflare Worker backend for the Siraj Arabic messaging application.

## Development branch

All current work is isolated on `feature/siraj-foundation-v1`. The default `main` branch has not been changed.

## Existing services

- D1 database: `siraj-db`
- Worker: `siraj-api`
- Vercel proxy forwards REST requests to the Worker.
- Existing user accounts, friendships, messages and device-token records are retained.

## Added in this branch

- Direct contact creation: `POST /api/contacts` (username, phone or user ID; no friend-request UX).
- Group APIs: `GET/POST /api/groups`, `POST /api/groups/:id/members`, and `GET/POST /api/groups/:id/messages`.
- Private attachment upload: `POST /api/media` using raw request bytes and headers `X-File-Name` plus exactly one of `X-Recipient-Id` or `X-Group-Id`.
- Authorized attachment download: `GET /api/media/:id`.
- Attachment binaries are stored privately in Tigris through its S3-compatible API; access keys remain Worker secrets.
- A recipient snapshot is stored for each attachment. Direct-chat files are eligible for deletion after the recipient downloads them; group files are eligible after every recipient in the snapshot downloads them.
- Uncollected files expire after 7 days. The Worker hourly scheduled task removes expired objects and marks storage metadata as deleted; chat message rows remain.
- Upload limit: 20 MiB per file.

## Required setup before deployment

1. Create a private Tigris bucket named `siraj-media`.
2. Create a Tigris access key with access limited to that bucket.
3. Add Worker secrets (never commit these values): `TIGRIS_ACCESS_KEY_ID` and `TIGRIS_SECRET_ACCESS_KEY`.
4. Confirm the Worker variable `TIGRIS_BUCKET=siraj-media` is set in `wrangler.toml`.
5. Apply `migrations/0001_groups_media.sql` if it has not already been applied to the existing `siraj-db`.
6. Apply `migrations/0002_tigris_retention.sql` once to the same D1 database.
7. Deploy the Worker from this branch after the bucket, secrets and migrations are ready.
8. Deploy the updated Vercel proxy files and test upload/download on a non-production test account before enabling for users.
9. Build and test the Flutter client package separately.

Do not delete or recreate the existing D1 database. Migrations add tables/columns and do not drop existing user or message records. These repository commits do not create the Tigris bucket, add secrets, apply D1 migrations, or deploy production.

## Security notes

- Attachment downloads require authentication and a matching sender/recipient snapshot.
- Files are private and served with `Cache-Control: private, no-store`.
- The 7-day expiry is a fallback; it is not a promise that a file remains available if every recipient downloads it earlier.
- This is not end-to-end encryption. Transport security and access checks do not replace E2E encryption.
- Do not upload secrets, tokens or passwords into this repository.
