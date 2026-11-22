-- Preview/test schema for message reactions and per-user conversation pins.
-- Do not apply to production until its schema and rollout are explicitly reviewed.
CREATE TABLE IF NOT EXISTS message_reactions (
  scope_type TEXT NOT NULL CHECK (scope_type IN ('private', 'group')),
  scope_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  emoji TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (scope_type, scope_id, message_id, user_id, emoji)
);
CREATE INDEX IF NOT EXISTS idx_message_reactions_message
  ON message_reactions(scope_type, scope_id, message_id);
CREATE TABLE IF NOT EXISTS pinned_messages (
  scope_type TEXT NOT NULL CHECK (scope_type IN ('private', 'group')),
  scope_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  pinned_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (scope_type, scope_id, message_id, pinned_by)
);
CREATE INDEX IF NOT EXISTS idx_pinned_messages_conversation
  ON pinned_messages(scope_type, scope_id, created_at DESC);
