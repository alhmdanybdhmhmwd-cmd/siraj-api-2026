-- Recovery codes are stored as salted SHA-256 digests only.
-- A code is high entropy (160 random bits), single-use, and rotated on demand.
CREATE TABLE IF NOT EXISTS recovery_codes (
  user_id TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  code_salt TEXT NOT NULL,
  expires_at INTEGER,
  consumed_at INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS recovery_rate_limits (
  bucket_key TEXT PRIMARY KEY,
  window_started INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_recovery_rate_limits_window
  ON recovery_rate_limits(window_started);

-- Revoke existing sessions immediately after a recovery-code password reset.
CREATE TABLE IF NOT EXISTS recovery_token_revocations (
  user_id TEXT PRIMARY KEY,
  revoked_at_ms INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
