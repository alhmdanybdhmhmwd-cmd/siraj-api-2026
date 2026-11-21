-- Preview/test-only group role extension. Never apply to production without schema review.
-- Owners remain authoritative in chat_groups.owner_id; this table stores only
-- optional admin assignments. Members without a row are ordinary members.
CREATE TABLE IF NOT EXISTS group_member_roles (
  group_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'member')),
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (group_id, user_id),
  FOREIGN KEY (group_id, user_id)
    REFERENCES group_members(group_id, user_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_group_member_roles_role
  ON group_member_roles(group_id, role, user_id);
