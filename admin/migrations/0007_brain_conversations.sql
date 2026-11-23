-- Persistent BARQ Brain conversations. Apply only to dedicated Admin Preview D1.
CREATE TABLE IF NOT EXISTS admin_brain_conversations (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (workspace_id) REFERENCES admin_workspaces(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_admin_brain_conversations_workspace_updated
  ON admin_brain_conversations(workspace_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS admin_brain_messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  workspace_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('user','assistant')),
  content TEXT NOT NULL CHECK (length(content) BETWEEN 1 AND 12000),
  source_refs_json TEXT NOT NULL DEFAULT '[]',
  model TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (conversation_id) REFERENCES admin_brain_conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (workspace_id) REFERENCES admin_workspaces(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_admin_brain_messages_conversation_time
  ON admin_brain_messages(conversation_id, created_at ASC);
