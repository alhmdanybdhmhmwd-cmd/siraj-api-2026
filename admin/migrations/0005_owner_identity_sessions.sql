-- Google OIDC owner identity and revocable Admin device sessions.
-- Apply only to a dedicated BARQ Admin Preview D1 database.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS admin_owner_devices (
  id TEXT PRIMARY KEY,
  owner_subject TEXT NOT NULL,
  device_name TEXT NOT NULL DEFAULT 'Android device',
  platform TEXT NOT NULL DEFAULT 'android',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_admin_owner_devices_owner
  ON admin_owner_devices(owner_subject, revoked_at, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS admin_owner_sessions (
  id TEXT PRIMARY KEY,
  owner_subject TEXT NOT NULL,
  device_id TEXT NOT NULL,
  refresh_token_hash TEXT NOT NULL,
  refresh_expires_at TEXT NOT NULL,
  refresh_version INTEGER NOT NULL DEFAULT 1 CHECK (refresh_version > 0),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked_at TEXT,
  FOREIGN KEY (device_id) REFERENCES admin_owner_devices(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_admin_owner_sessions_device
  ON admin_owner_sessions(device_id, revoked_at);
CREATE INDEX IF NOT EXISTS idx_admin_owner_sessions_owner
  ON admin_owner_sessions(owner_subject, revoked_at, refresh_expires_at);

-- A Google ID token nonce can establish at most one Admin session.
CREATE TABLE IF NOT EXISTS admin_oidc_nonce_uses (
  nonce_hash TEXT PRIMARY KEY,
  owner_subject TEXT NOT NULL,
  used_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_admin_oidc_nonce_expiry
  ON admin_oidc_nonce_uses(expires_at);

-- Short-window auth throttles only; no daily or monthly image quotas are introduced.
CREATE TABLE IF NOT EXISTS admin_auth_rate_limits (
  bucket_key TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0 CHECK (request_count >= 0),
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (bucket_key, window_start)
);
CREATE INDEX IF NOT EXISTS idx_admin_auth_rate_limits_window
  ON admin_auth_rate_limits(window_start);
