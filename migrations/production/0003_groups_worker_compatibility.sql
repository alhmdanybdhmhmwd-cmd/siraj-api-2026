-- Production compatibility bridge: the deployed D1 schema stores groups in
-- `groups` (created_by), while the Worker contract uses `chat_groups`
-- (owner_id). A view + INSTEAD OF triggers preserve the existing table and
-- all foreign keys held by group_members, group_messages, and media_assets.
CREATE VIEW IF NOT EXISTS chat_groups AS
SELECT id, name, description, created_by AS owner_id, created_at
FROM groups;

CREATE TRIGGER IF NOT EXISTS trg_chat_groups_insert
INSTEAD OF INSERT ON chat_groups
BEGIN
  INSERT INTO groups (id, name, description, created_by, created_at)
  VALUES (
    NEW.id, NEW.name, COALESCE(NEW.description, ''),
    NEW.owner_id, COALESCE(NEW.created_at, CURRENT_TIMESTAMP)
  );
END;

CREATE TRIGGER IF NOT EXISTS trg_chat_groups_update
INSTEAD OF UPDATE ON chat_groups
BEGIN
  UPDATE groups
  SET id = NEW.id,
      name = NEW.name,
      description = COALESCE(NEW.description, ''),
      created_by = NEW.owner_id,
      created_at = NEW.created_at
  WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_chat_groups_delete
INSTEAD OF DELETE ON chat_groups
BEGIN
  DELETE FROM groups WHERE id = OLD.id;
END;

-- Production group_messages predates reply/edit support. Additive columns keep
-- existing messages intact while bringing the table up to the Worker contract.
ALTER TABLE group_messages ADD COLUMN reply_to_id TEXT;
ALTER TABLE group_messages ADD COLUMN reply_to_body TEXT;
ALTER TABLE group_messages ADD COLUMN reply_to_sender_id TEXT;
ALTER TABLE group_messages ADD COLUMN edited_at TEXT;

CREATE INDEX IF NOT EXISTS idx_group_messages_reply_target
  ON group_messages(reply_to_id);

-- Optional admin assignments; existing group_members rows remain ordinary
-- members unless explicitly promoted.
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
