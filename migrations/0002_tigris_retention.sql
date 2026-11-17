-- Siraj Tigris attachment retention and per-recipient download tracking.
-- Apply once to the existing siraj-db D1 database after the earlier groups/media migration.
ALTER TABLE media_assets ADD COLUMN expires_at TEXT;
ALTER TABLE media_assets ADD COLUMN storage_deleted INTEGER NOT NULL DEFAULT 0;

UPDATE media_assets
SET expires_at = datetime(created_at, '+7 days')
WHERE expires_at IS NULL;

CREATE TABLE IF NOT EXISTS media_recipients (
  media_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (media_id, user_id),
  FOREIGN KEY (media_id) REFERENCES media_assets(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS media_downloads (
  media_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  downloaded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (media_id, user_id),
  FOREIGN KEY (media_id) REFERENCES media_assets(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_media_assets_expiry
  ON media_assets(storage_deleted, expires_at);
