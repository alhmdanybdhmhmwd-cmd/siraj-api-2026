import sqlite3
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSPECTION_SQL = ROOT / "docs" / "d1-schema-inspection.sql"


def execute_selects(connection, source):
    statement = ""
    results = []
    for line in source.splitlines():
        if line.lstrip().startswith("--"):
            continue
        statement += line + "\n"
        if sqlite3.complete_statement(statement):
            candidate = statement.strip()
            statement = ""
            if candidate and not candidate.startswith("--"):
                cursor = connection.execute(candidate)
                if cursor.description:
                    results.append((cursor.description, cursor.fetchall()))
    if statement.strip():
        raise AssertionError("Incomplete SQL statement in inspection script")
    return results


class D1SchemaInspectionTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys = ON")
        self.db.executescript("""
            CREATE TABLE users (
                id TEXT PRIMARY KEY,
                username TEXT NOT NULL UNIQUE
            );
            CREATE TABLE friendships (
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                friend_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                UNIQUE(user_id, friend_id)
            );
            CREATE TABLE messages (
                id TEXT PRIMARY KEY,
                sender_id TEXT NOT NULL REFERENCES users(id),
                receiver_id TEXT NOT NULL REFERENCES users(id),
                body TEXT NOT NULL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                read_at TEXT
            );
            CREATE INDEX idx_messages_conversation
                ON messages(sender_id, receiver_id, created_at);
        """)

    def tearDown(self):
        self.db.close()

    def test_inspection_script_reports_catalog_columns_foreign_keys_and_indexes(self):
        results = execute_selects(
            self.db, INSPECTION_SQL.read_text(encoding="utf-8")
        )
        self.assertEqual(len(results), 4)

        catalog_rows = results[0][1]
        catalog_names = {row[1] for row in catalog_rows}
        self.assertIn("users", catalog_names)
        self.assertIn("friendships", catalog_names)
        self.assertIn("messages", catalog_names)
        self.assertIn("idx_messages_conversation", catalog_names)

        column_rows = results[1][1]
        columns = {(row[0], row[2]) for row in column_rows}
        self.assertIn(("users", "username"), columns)
        self.assertIn(("friendships", "friend_id"), columns)
        self.assertIn(("messages", "read_at"), columns)

        foreign_key_rows = results[2][1]
        foreign_keys = {(row[0], row[4], row[3]) for row in foreign_key_rows}
        self.assertIn(("friendships", "user_id", "users"), foreign_keys)
        self.assertIn(("messages", "sender_id", "users"), foreign_keys)

        index_rows = results[3][1]
        indexes = {(row[0], row[1], row[7]) for row in index_rows}
        self.assertIn(
            ("messages", "idx_messages_conversation", "sender_id"), indexes
        )
        self.assertIn(
            ("friendships", "sqlite_autoindex_friendships_1", "user_id"),
            indexes,
        )


if __name__ == "__main__":
    unittest.main()
