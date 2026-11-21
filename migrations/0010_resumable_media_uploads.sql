-- Resumable media-upload sessions are temporary; completed media objects are not expired by this table.
CREATE TABLE IF NOT EXISTS media_upload_sessions (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  recipient_id TEXT,
  group_id TEXT,
  object_key TEXT NOT NULL UNIQUE,
  storage_upload_id TEXT NOT NULL UNIQUE,
  file_name TEXT NOT NULL,
  content_type TEXT NOT NULL,
  total_size INTEGER NOT NULL CHECK (total_size BETWEEN 1 AND 62914560),
  part_size INTEGER NOT NULL CHECK (part_size = 5242880),
  expected_parts INTEGER NOT NULL CHECK (expected_parts BETWEEN 1 AND 12),
  idempotency_key TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'uploading'
    CHECK (state IN ('uploading', 'completing', 'completed', 'aborted', 'failed')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL,
  completed_at TEXT,
  FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (owner_id, idempotency_key),
  CHECK ((recipient_id IS NOT NULL AND group_id IS NULL) OR
         (recipient_id IS NULL AND group_id IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_media_upload_sessions_expiry
  ON media_upload_sessions(state, expires_at);

CREATE INDEX IF NOT EXISTS idx_media_upload_sessions_owner
  ON media_upload_sessions(owner_id, state, updated_at);

CREATE TABLE IF NOT EXISTS media_upload_parts (
  session_id TEXT NOT NULL,
  part_number INTEGER NOT NULL CHECK (part_number BETWEEN 1 AND 12),
  etag TEXT NOT NULL,
  size INTEGER NOT NULL CHECK (size BETWEEN 1 AND 5242880),
  uploaded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (session_id, part_number),
  FOREIGN KEY (session_id) REFERENCES media_upload_sessions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_media_upload_parts_session
  ON media_upload_parts(session_id, part_number);
