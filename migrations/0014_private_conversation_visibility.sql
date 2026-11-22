-- Preview schema for per-user private conversation deletion and clearing.
-- Hidden messages remain intact for the other participant.
CREATE TABLE IF NOT EXISTS hidden_private_messages (
  user_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  hidden_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, message_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_hidden_private_messages_message
  ON hidden_private_messages(message_id);
CREATE TABLE IF NOT EXISTS private_conversation_state (
  user_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  hidden_at TEXT,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, peer_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (peer_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_private_conversation_state_peer
  ON private_conversation_state(peer_id, user_id);
