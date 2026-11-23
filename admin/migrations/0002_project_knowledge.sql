-- Versioned project context index for BARQ Brain. Preview/Admin database only.
CREATE TABLE IF NOT EXISTS admin_project_knowledge (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  source_type TEXT NOT NULL CHECK (source_type IN (
    'repository_file','product_requirement','architecture_decision',
    'api_contract','test_report','runbook','launch_material'
  )),
  source_path TEXT NOT NULL,
  source_revision TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 180),
  content TEXT NOT NULL CHECK (length(content) BETWEEN 1 AND 24000),
  content_hash TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (workspace_id) REFERENCES admin_workspaces(id) ON DELETE CASCADE,
  UNIQUE (workspace_id, source_path, source_revision)
);

CREATE INDEX IF NOT EXISTS idx_admin_knowledge_workspace_updated
  ON admin_project_knowledge(workspace_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_knowledge_source
  ON admin_project_knowledge(workspace_id, source_type, source_path);
