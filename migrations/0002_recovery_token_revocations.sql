-- Revoke previously issued login sessions after a successful password reset.
CREATE TABLE IF NOT EXISTS recovery_token_revocations (
  user_id TEXT PRIMARY KEY,
  revoked_at_ms INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
