-- Track trusted app installations independently for each account.
CREATE TABLE IF NOT EXISTS device_sessions (
  user_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  device_name TEXT NOT NULL DEFAULT 'جهاز غير معروف',
  first_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked_at TEXT,
  PRIMARY KEY (user_id, device_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_device_sessions_user_active
  ON device_sessions(user_id, revoked_at, last_seen_at);
