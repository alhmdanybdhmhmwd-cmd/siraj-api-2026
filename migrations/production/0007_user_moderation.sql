-- Additive moderation records for BARQ user reports and owner account suspensions.
-- Apply only after reviewing the matching Preview migration and release checklist.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS user_reports (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL,
  reported_user_id TEXT NOT NULL,
  category TEXT NOT NULL,
  details TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'reviewed', 'dismissed')),
  reviewed_by TEXT,
  reviewed_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (reporter_id <> reported_user_id),
  FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (reported_user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_user_reports_target_status_time
  ON user_reports(reported_user_id, status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_reports_one_pending_per_pair
  ON user_reports(reporter_id, reported_user_id) WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS admin_user_suspensions (
  user_id TEXT PRIMARY KEY,
  reason TEXT NOT NULL,
  suspended_by TEXT NOT NULL,
  suspended_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT,
  lifted_by TEXT,
  lifted_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_admin_user_suspensions_active
  ON admin_user_suspensions(lifted_at, expires_at);

CREATE TABLE IF NOT EXISTS admin_user_moderation_actions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('suspend', 'unsuspend')),
  reason TEXT NOT NULL,
  actor_subject TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_admin_user_moderation_actions_user_time
  ON admin_user_moderation_actions(user_id, created_at DESC);
