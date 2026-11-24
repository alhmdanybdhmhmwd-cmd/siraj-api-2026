-- Preserve historical knowledge revisions while identifying sources absent from the latest complete repository index.
ALTER TABLE admin_project_knowledge
  ADD COLUMN last_seen_revision TEXT NOT NULL DEFAULT '';

ALTER TABLE admin_project_knowledge
  ADD COLUMN is_stale INTEGER NOT NULL DEFAULT 0 CHECK (is_stale IN (0, 1));

CREATE INDEX IF NOT EXISTS idx_admin_project_knowledge_freshness
  ON admin_project_knowledge (workspace_id, is_stale, source_path);
