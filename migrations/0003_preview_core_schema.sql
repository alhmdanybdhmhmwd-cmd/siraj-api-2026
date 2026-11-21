-- Preview-only base schema for exercising the current Worker contract.
-- This is NOT an export of production D1 and must NEVER be applied to wrangler.toml.
-- Column names and write/read shapes are derived from src/src/index.js.
-- Constraints/indexes here are deliberately scoped to the isolated Preview fixture.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL COLLATE NOCASE UNIQUE,
  display_name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  phone TEXT
);

-- Phone is intentionally not UNIQUE: the Worker detects equivalent local and
-- international forms, which a simple UNIQUE(phone) constraint cannot model.
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);

CREATE TABLE IF NOT EXISTS friendships (
  user_id TEXT NOT NULL,
  friend_id TEXT NOT NULL,
  UNIQUE(user_id, friend_id),
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (friend_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_friend_id ON friendships(friend_id, user_id);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  sender_id TEXT NOT NULL,
  receiver_id TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  read_at TEXT,
  FOREIGN KEY (sender_id) REFERENCES users(id),
  FOREIGN KEY (receiver_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation
  ON messages(sender_id, receiver_id, created_at, id);

CREATE INDEX IF NOT EXISTS idx_messages_reverse_conversation
  ON messages(receiver_id, sender_id, created_at, id);
