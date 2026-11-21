-- Preview/test-only schema extension for quoted replies.
-- Never apply this migration to production without first verifying its schema.
-- The isolated core fixture does not otherwise create group tables, so define
-- the same minimal contract used by the Worker before adding reply metadata.
CREATE TABLE IF NOT EXISTS chat_groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  owner_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS group_members (
  group_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (group_id, user_id),
  FOREIGN KEY (group_id) REFERENCES chat_groups(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (group_id) REFERENCES chat_groups(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
);

ALTER TABLE messages ADD COLUMN reply_to_id TEXT;
ALTER TABLE messages ADD COLUMN reply_to_body TEXT;
ALTER TABLE messages ADD COLUMN reply_to_sender_id TEXT;

ALTER TABLE group_messages ADD COLUMN reply_to_id TEXT;
ALTER TABLE group_messages ADD COLUMN reply_to_body TEXT;
ALTER TABLE group_messages ADD COLUMN reply_to_sender_id TEXT;

CREATE INDEX IF NOT EXISTS idx_messages_reply_target ON messages(reply_to_id);
CREATE INDEX IF NOT EXISTS idx_group_messages_reply_target ON group_messages(reply_to_id);
