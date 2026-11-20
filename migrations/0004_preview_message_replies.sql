-- Preview/test-only schema extension for quoted replies.
-- Never apply this migration to production without first verifying its schema.
ALTER TABLE messages ADD COLUMN reply_to_id TEXT;
ALTER TABLE messages ADD COLUMN reply_to_body TEXT;
ALTER TABLE messages ADD COLUMN reply_to_sender_id TEXT;

ALTER TABLE group_messages ADD COLUMN reply_to_id TEXT;
ALTER TABLE group_messages ADD COLUMN reply_to_body TEXT;
ALTER TABLE group_messages ADD COLUMN reply_to_sender_id TEXT;

CREATE INDEX IF NOT EXISTS idx_messages_reply_target ON messages(reply_to_id);
CREATE INDEX IF NOT EXISTS idx_group_messages_reply_target ON group_messages(reply_to_id);
