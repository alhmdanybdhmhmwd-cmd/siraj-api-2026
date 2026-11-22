-- Preview/test schema extension for editable messages.
-- Do not apply to production until its schema and rollout are explicitly reviewed.
ALTER TABLE messages ADD COLUMN edited_at TEXT;
ALTER TABLE group_messages ADD COLUMN edited_at TEXT;
