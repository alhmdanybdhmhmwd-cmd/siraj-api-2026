-- Account-scoped hiding for ephemeral messages when a private chat is cleared/deleted.
CREATE TABLE IF NOT EXISTS hidden_ephemeral_messages (
  user_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  hidden_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, message_id)
);
CREATE INDEX IF NOT EXISTS idx_hidden_ephemeral_messages_message
  ON hidden_ephemeral_messages(message_id);
