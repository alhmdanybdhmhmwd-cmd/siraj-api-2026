-- Retain legacy chat attachments without changing SPARK or private-memory lifetimes.
-- This migration is intentionally data-scoped: only media_access rows referenced by
-- private/group message attachment payloads are made permanent. Status media keeps
-- its own expiry policy, and unrelated expiration records are left untouched.
CREATE TABLE IF NOT EXISTS media_expirations (
  object_key TEXT PRIMARY KEY,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS media_access (
  object_key TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  recipient_id TEXT,
  group_id TEXT,
  file_name TEXT NOT NULL,
  content_type TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

-- First, remove the scheduled expiry entries for existing chat attachments.
-- The object keys are matched against the attachmentId stored in message JSON.
DELETE FROM media_expirations
WHERE object_key IN (
  SELECT ma.object_key
  FROM media_access AS ma
  WHERE EXISTS (
    SELECT 1 FROM messages AS m
    WHERE json_valid(m.body)
      AND json_extract(m.body, '$.type') = 'attachment'
      AND json_extract(m.body, '$.attachmentId') = ma.object_key
  )
  OR EXISTS (
    SELECT 1 FROM group_messages AS gm
    WHERE json_valid(gm.body)
      AND json_extract(gm.body, '$.type') = 'attachment'
      AND json_extract(gm.body, '$.attachmentId') = ma.object_key
  )
);

-- Keep the access row as a durable authorization record. The far-future sentinel
-- is consistent with the current Worker logic and is not an automatic deletion date.
UPDATE media_access
SET expires_at = '9999-12-31T23:59:59.999Z'
WHERE EXISTS (
  SELECT 1 FROM messages AS m
  WHERE json_valid(m.body)
    AND json_extract(m.body, '$.type') = 'attachment'
    AND json_extract(m.body, '$.attachmentId') = media_access.object_key
)
OR EXISTS (
  SELECT 1 FROM group_messages AS gm
  WHERE json_valid(gm.body)
    AND json_extract(gm.body, '$.type') = 'attachment'
    AND json_extract(gm.body, '$.attachmentId') = media_access.object_key
);
