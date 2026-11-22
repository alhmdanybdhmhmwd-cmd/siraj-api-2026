-- Ephemeral messages are isolated from regular chat messages and cascade with either user.
CREATE TABLE IF NOT EXISTS ephemeral_messages (
  id TEXT PRIMARY KEY,
  sender_id TEXT NOT NULL,
  receiver_id TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),
  read_at INTEGER,
  delete_at INTEGER,
  FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ephemeral_conversation
  ON ephemeral_messages(sender_id, receiver_id, created_at);

CREATE INDEX IF NOT EXISTS idx_ephemeral_expiration
  ON ephemeral_messages(delete_at);
