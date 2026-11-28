CREATE TABLE IF NOT EXISTS admin_ai_usage_limits (
  workspace_id TEXT NOT NULL REFERENCES admin_workspaces(id) ON DELETE CASCADE,
  window_start INTEGER NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 0 CHECK (request_count BETWEEN 0 AND 3),
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (workspace_id, window_start)
);
