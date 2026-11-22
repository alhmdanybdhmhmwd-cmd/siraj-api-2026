#!/usr/bin/env python3
"""SQLite regression tests for account-scoped private conversation clearing/deletion."""
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / "migrations" / "0014_private_conversation_visibility.sql"
PRODUCTION = ROOT / "migrations" / "production" / "0004_private_conversation_visibility.sql"


def build_db(migration: Path) -> sqlite3.Connection:
    db = sqlite3.connect(":memory:")
    db.execute("PRAGMA foreign_keys = ON")
    db.executescript("""
      CREATE TABLE users (id TEXT PRIMARY KEY);
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        receiver_id TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (sender_id) REFERENCES users(id),
        FOREIGN KEY (receiver_id) REFERENCES users(id)
      );
    """)
    db.executemany("INSERT INTO users(id) VALUES (?)", [("alice",), ("bob",)])
    db.executemany(
        "INSERT INTO messages(id, sender_id, receiver_id, body) VALUES (?, ?, ?, ?)",
        [
            ("m1", "alice", "bob", "from alice"),
            ("m2", "bob", "alice", "from bob"),
        ],
    )
    db.executescript(migration.read_text(encoding="utf-8"))
    return db


def visible_ids(db: sqlite3.Connection, user_id: str) -> set[str]:
    rows = db.execute("""
      SELECT m.id FROM messages m
      WHERE ((m.sender_id = 'alice' AND m.receiver_id = 'bob')
          OR (m.sender_id = 'bob' AND m.receiver_id = 'alice'))
        AND NOT EXISTS (
          SELECT 1 FROM hidden_private_messages h
          WHERE h.user_id = ? AND h.message_id = m.id
        )
    """, (user_id,)).fetchall()
    return {row[0] for row in rows}


def verify(migration: Path) -> None:
    db = build_db(migration)
    # Clear history: hide every existing message only for Alice.
    db.execute("""
      INSERT OR IGNORE INTO hidden_private_messages(user_id, message_id)
      SELECT 'alice', id FROM messages
      WHERE (sender_id = 'alice' AND receiver_id = 'bob')
         OR (sender_id = 'bob' AND receiver_id = 'alice')
    """)
    assert visible_ids(db, "alice") == set()
    assert visible_ids(db, "bob") == {"m1", "m2"}

    # Deleting the conversation hides it in Alice's chat list, not her contact.
    db.execute("""
      INSERT INTO private_conversation_state(user_id, peer_id, hidden_at)
      VALUES ('alice', 'bob', CURRENT_TIMESTAMP)
      ON CONFLICT(user_id, peer_id) DO UPDATE SET hidden_at = excluded.hidden_at
    """)
    hidden = db.execute("""
      SELECT hidden_at FROM private_conversation_state
      WHERE user_id = 'alice' AND peer_id = 'bob'
    """).fetchone()
    assert hidden and hidden[0] is not None
    assert db.execute("SELECT COUNT(*) FROM users WHERE id = 'bob'").fetchone()[0] == 1

    # A new incoming message restores the chat row, but not old hidden history.
    db.execute("""
      INSERT INTO messages(id, sender_id, receiver_id, body)
      VALUES ('m3', 'bob', 'alice', 'new message')
    """)
    db.execute("""
      INSERT INTO private_conversation_state(user_id, peer_id, hidden_at)
      VALUES ('alice', 'bob', NULL)
      ON CONFLICT(user_id, peer_id) DO UPDATE SET hidden_at = NULL
    """)
    assert visible_ids(db, "alice") == {"m3"}
    assert visible_ids(db, "bob") == {"m1", "m2", "m3"}
    assert db.execute("PRAGMA foreign_key_check").fetchall() == []
    db.close()


if __name__ == "__main__":
    verify(PREVIEW)
    verify(PRODUCTION)
    print("Private conversation visibility migration tests passed (Preview + production).")
