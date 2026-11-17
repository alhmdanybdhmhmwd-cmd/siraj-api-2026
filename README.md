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
- Attachment payloads are recorded as messages, and binary data is stored in R2 rather than D1.
- Upload limit: 20 MiB per file.

## Required setup before deployment

1. Create a Cloudflare R2 bucket named `siraj-media` in the same account as the Worker.
2. Apply `migrations/0001_groups_media.sql` once to the existing `siraj-db` D1 database.
3. Deploy the Worker from this branch after the bucket and migration are ready.
4. Deploy the updated Vercel proxy files (`server.js` and `api/[...path].js)) so the attachment headers and binary request body are forwarded.
5. Build and test the Flutter client package separately.

Do not delete or recreate the existing D1 database. The migration adds new tables and does not drop existing tables. No production deployment or live D1 migration is performed by these repository commits.

## Security notes

- Attachment downloads require authentication and matching sender/recipient or group membership.
- Files are served as attachments with private, no-store caching.
- This is not end-to-end encryption. Transport security and access checks do not replace E2E encryption.
- Do not upload secrets, tokens or passwords into this repository.
