-- Durable staging metadata for small HTTP transport chunks.
-- Staged objects are temporary; completed media objects keep their independent lifetime.
CREATE TABLE IF NOT EXISTS media_upload_chunks (
  session_id TEXT NOT NULL,
  chunk_number INTEGER NOT NULL CHECK (chunk_number BETWEEN 1 AND 60),
  size INTEGER NOT NULL CHECK (size BETWEEN 1 AND 1048576),
  uploaded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (session_id, chunk_number),
  FOREIGN KEY (session_id) REFERENCES media_upload_sessions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_media_upload_chunks_session
  ON media_upload_chunks(session_id, chunk_number);
