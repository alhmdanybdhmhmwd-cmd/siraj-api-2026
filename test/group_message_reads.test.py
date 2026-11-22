import sqlite3

db = sqlite3.connect(":memory:")
db.execute("PRAGMA foreign_keys = ON")
db.executescript("""
CREATE TABLE users (id TEXT PRIMARY KEY);
CREATE TABLE group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL
);
CREATE TABLE group_message_reads (
  message_id TEXT NOT NULL REFERENCES group_messages(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  read_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (message_id, user_id)
);
INSERT INTO users (id) VALUES ('alice'), ('bob'), ('carol');
INSERT INTO group_messages (id, group_id, sender_id, body)
VALUES ('m1', 'g1', 'alice', 'hello'), ('m2', 'g1', 'bob', 'hi');
""")

def mark_page_read(user_id, group_id, message_ids):
    placeholders = ",".join("?" for _ in message_ids)
    db.execute(
        f"""INSERT OR IGNORE INTO group_message_reads (message_id, user_id)
            SELECT id, ? FROM group_messages
            WHERE group_id = ? AND sender_id != ? AND id IN ({placeholders})""",
        (user_id, group_id, user_id, *message_ids),
    )

def seen_count(message_id):
    return db.execute(
        "SELECT COUNT(*) FROM group_message_reads WHERE message_id = ?",
        (message_id,),
    ).fetchone()[0]

mark_page_read("bob", "g1", ["m1", "m2"])
assert seen_count("m1") == 1
assert seen_count("m2") == 0, "a sender must not mark their own message as read"

mark_page_read("carol", "g1", ["m1", "m2"])
assert seen_count("m1") == 2
assert seen_count("m2") == 1

mark_page_read("carol", "g1", ["m1", "m2"])
assert seen_count("m1") == 2, "re-reading a page must not duplicate receipts"

db.execute("DELETE FROM group_messages WHERE id = 'm1'")
assert seen_count("m1") == 0, "message deletion must cascade its read receipts"

print("Group message read-receipt SQL checks passed.")
