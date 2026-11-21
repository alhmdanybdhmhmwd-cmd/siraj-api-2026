import sqlite3
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migrations" / "0001_recovery_codes.sql"


class RecoveryMigrationTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys = ON")
        # The users table belongs to the existing application schema.
        self.db.execute("CREATE TABLE users (id TEXT PRIMARY KEY)")
        self.db.executescript(MIGRATION.read_text(encoding="utf-8"))

    def tearDown(self):
        self.db.close()

    def test_migration_creates_recovery_tables_and_index(self):
        tables = {
            row[0] for row in self.db.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        indexes = {
            row[0] for row in self.db.execute(
                "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
        }
        self.assertIn("recovery_codes", tables)
        self.assertIn("recovery_rate_limits", tables)
        self.assertIn("idx_recovery_rate_limits_window", indexes)

    def test_recovery_code_requires_existing_user_and_cascades_on_delete(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                """INSERT INTO recovery_codes
                   (user_id, code_hash, code_salt, expires_at, created_at)
                   VALUES ('missing', 'hash', 'salt', 9999999999, 1)"""
            )

        self.db.execute("INSERT INTO users (id) VALUES ('user-1')")
        self.db.execute(
            """INSERT INTO recovery_codes
               (user_id, code_hash, code_salt, expires_at, created_at)
               VALUES ('user-1', 'hash', 'salt', 9999999999, 1)"""
        )
        self.db.execute("DELETE FROM users WHERE id = 'user-1'")
        self.assertEqual(
            self.db.execute("SELECT COUNT(*) FROM recovery_codes").fetchone()[0],
            0,
        )

    def test_recovery_rate_limit_upsert_resets_only_after_window(self):
        statement = """INSERT INTO recovery_rate_limits
            (bucket_key, window_started, attempts) VALUES (?, ?, 1)
            ON CONFLICT(bucket_key) DO UPDATE SET
              window_started = CASE
                WHEN recovery_rate_limits.window_started <= ?
                THEN excluded.window_started
                ELSE recovery_rate_limits.window_started END,
              attempts = CASE
                WHEN recovery_rate_limits.window_started <= ?
                THEN 1 ELSE recovery_rate_limits.attempts + 1 END"""

        for now in (1000, 1001, 1002):
            self.db.execute(statement, ("bucket", now, now - 900, now - 900))
        self.assertEqual(
            self.db.execute(
                "SELECT attempts FROM recovery_rate_limits WHERE bucket_key = 'bucket'"
            ).fetchone()[0],
            3,
        )

        now = 1903
        self.db.execute(statement, ("bucket", now, now - 900, now - 900))
        row = self.db.execute(
            "SELECT window_started, attempts FROM recovery_rate_limits WHERE bucket_key = 'bucket'"
        ).fetchone()
        self.assertEqual(row, (1903, 1))


if __name__ == "__main__":
    unittest.main()
