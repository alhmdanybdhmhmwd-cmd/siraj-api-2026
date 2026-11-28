-- BARQ Admin foundation schema. For shared runtime, apply to BARQ D1 only after explicit owner approval; standalone Preview may use its isolated Admin D1.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS admin_workspaces (
  id TEXT PRIMARY KEY,
  owner_subject TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL DEFAULT 'BARQ Workspace',
  current_project TEXT NOT NULL DEFAULT 'BARQ',
  current_phase TEXT NOT NULL DEFAULT 'admin-foundation',
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS admin_tasks (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  created_by TEXT NOT NULL,
  title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 180),
  description TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued','running','paused','needs_approval','failed','completed','cancelled')),
  priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  checkpoint_version INTEGER NOT NULL DEFAULT 0 CHECK (checkpoint_version >= 0),
  last_checkpoint_id TEXT,
  next_action TEXT NOT NULL DEFAULT '',
  idempotency_key TEXT,
  lease_owner TEXT,
  lease_expires_at TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (workspace_id) REFERENCES admin_workspaces(id) ON DELETE CASCADE,
  UNIQUE (workspace_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_admin_tasks_workspace_updated
  ON admin_tasks(workspace_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_tasks_status_lease
  ON admin_tasks(status, lease_expires_at);

CREATE TABLE IF NOT EXISTS admin_task_checkpoints (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  sequence INTEGER NOT NULL CHECK (sequence > 0),
  input_json TEXT NOT NULL DEFAULT '{}',
  output_json TEXT NOT NULL DEFAULT '{}',
  completed_step TEXT NOT NULL DEFAULT '',
  next_action TEXT NOT NULL DEFAULT '',
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (task_id) REFERENCES admin_tasks(id) ON DELETE CASCADE,
  UNIQUE (task_id, sequence)
);

CREATE TABLE IF NOT EXISTS admin_approvals (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  task_id TEXT,
  requested_by TEXT NOT NULL,
  action_type TEXT NOT NULL,
  action_preview_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  decided_by TEXT,
  decision_note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decided_at TEXT,
  FOREIGN KEY (workspace_id) REFERENCES admin_workspaces(id) ON DELETE CASCADE,
  FOREIGN KEY (task_id) REFERENCES admin_tasks(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS admin_audit_events (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  actor_subject TEXT NOT NULL,
  actor_device_id TEXT NOT NULL DEFAULT '',
  event_type TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (workspace_id) REFERENCES admin_workspaces(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_workspace_time
  ON admin_audit_events(workspace_id, created_at DESC);

-- Audit records are append-only, including for privileged application code.
CREATE TRIGGER IF NOT EXISTS admin_audit_no_update
BEFORE UPDATE ON admin_audit_events
BEGIN
  SELECT RAISE(ABORT, 'admin audit events are immutable');
END;

CREATE TRIGGER IF NOT EXISTS admin_audit_no_delete
BEFORE DELETE ON admin_audit_events
BEGIN
  SELECT RAISE(ABORT, 'admin audit events are immutable');
END;
