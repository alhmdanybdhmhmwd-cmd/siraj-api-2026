import sqlite3
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = sorted((ROOT / "migrations").glob("*.sql"))


class RecoveryMigrationTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys = ON")
        for migration in MIGRATIONS:
            self.db.executescript(migration.read_text(encoding="utf-8"))

    def tearDown(self):
        self.db.close()


    def test_preview_core_schema_matches_worker_contract(self):
        columns = {
            row[1] for row in self.db.execute("PRAGMA table_info(users)")
        }
        self.assertTrue({
            "id", "username", "display_name", "password_hash",
            "password_salt", "phone"
        }.issubset(columns))

        # Username uniqueness is enforced; phone intentionally is not, because
        # equivalent local/international forms are normalized in Worker logic.
        self.db.execute(
            """INSERT INTO users
               (id, username, display_name, password_hash, password_salt, phone)
               VALUES ('u1', 'sparkuser', 'Spark User', 'hash', 'salt', '+967700000001')"""
        )
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                """INSERT INTO users
                   (id, username, display_name, password_hash, password_salt, phone)
                   VALUES ('u2', 'SPARKUSER', 'Duplicate', 'hash', 'salt', '+967700000002')"""
            )
        self.db.execute(
            """INSERT INTO users
               (id, username, display_name, password_hash, password_salt, phone)
               VALUES ('u3', 'otheruser', 'Other User', 'hash', 'salt', '+967700000001')"""
        )

        self.db.execute(
            "INSERT INTO friendships (user_id, friend_id) VALUES ('u1', 'u3')"
        )
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                "INSERT INTO friendships (user_id, friend_id) VALUES ('u1', 'u3')"
            )

        self.db.execute(
            "INSERT INTO messages (id, sender_id, receiver_id, body) VALUES ('m1', 'u1', 'u3', 'hello')"
        )
        self.db.execute(
            "UPDATE messages SET read_at = CURRENT_TIMESTAMP WHERE id = 'm1' AND read_at IS NULL"
        )
        row = self.db.execute(
            "SELECT sender_id, receiver_id, body, created_at, read_at FROM messages WHERE id = 'm1'"
        ).fetchone()
        self.assertEqual(row[:3], ("u1", "u3", "hello"))
        self.assertTrue(row[3])
        self.assertTrue(row[4])

        foreign_keys = {
            (table, from_column, target_table)
            for table in ("friendships", "messages")
            for _, _, target_table, from_column, _, _, _, _ in self.db.execute(
                f"PRAGMA foreign_key_list({table})"
            )
        }
        self.assertIn(("friendships", "user_id", "users"), foreign_keys)
        self.assertIn(("friendships", "friend_id", "users"), foreign_keys)
        self.assertIn(("messages", "sender_id", "users"), foreign_keys)
        self.assertIn(("messages", "receiver_id", "users"), foreign_keys)

    def test_preview_message_edit_migration_adds_edited_timestamps(self):
        private_columns = {
            row[1] for row in self.db.execute("PRAGMA table_info(messages)")
        }
        group_columns = {
            row[1] for row in self.db.execute("PRAGMA table_info(group_messages)")
        }
        self.assertIn("edited_at", private_columns)
        self.assertIn("edited_at", group_columns)

        self.db.execute(
            "INSERT INTO users (id, username, display_name, password_hash, password_salt) VALUES ('u1', 'edituser', 'Edit User', 'hash', 'salt')"
        )
        self.db.execute(
            "INSERT INTO users (id, username, display_name, password_hash, password_salt) VALUES ('u2', 'otheredit', 'Other User', 'hash', 'salt')"
        )
        self.db.execute(
            "INSERT INTO messages (id, sender_id, receiver_id, body) VALUES ('edit-1', 'u1', 'u2', 'before')"
        )
        self.db.execute(
            "UPDATE messages SET body = 'after', edited_at = CURRENT_TIMESTAMP WHERE id = 'edit-1' AND sender_id = 'u1'"
        )
        body, edited_at = self.db.execute(
            "SELECT body, edited_at FROM messages WHERE id = 'edit-1'"
        ).fetchone()
        self.assertEqual(body, "after")
        self.assertTrue(edited_at)

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

        self.db.execute("INSERT INTO users (id, username, display_name, password_hash, password_salt, phone) VALUES ('user-1', 'user1', 'User One', 'hash', 'salt', NULL)")
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


    def test_revoked_sessions_store_only_hashes_and_expire_with_the_token(self):
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
        self.assertIn("revoked_sessions", tables)
        self.assertIn("idx_revoked_sessions_expiry", indexes)

        self.db.execute("INSERT INTO users (id, username, display_name, password_hash, password_salt, phone) VALUES ('user-1', 'user1', 'User One', 'hash', 'salt', NULL)")
        self.db.execute(
            """INSERT INTO revoked_sessions (token_hash, user_id, expires_at)
               VALUES ('sha256-digest-only', 'user-1', 2000)"""
        )
        self.assertEqual(
            self.db.execute(
                "SELECT expires_at FROM revoked_sessions WHERE token_hash = ?",
                ("sha256-digest-only",),
            ).fetchone()[0],
            2000,
        )
        self.db.execute("DELETE FROM users WHERE id = 'user-1'")
        self.assertEqual(
            self.db.execute("SELECT COUNT(*) FROM revoked_sessions").fetchone()[0],
            0,
        )


    def test_message_reactions_and_pins_are_idempotent_and_scoped(self):
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
        self.assertIn("message_reactions", tables)
        self.assertIn("pinned_messages", tables)
        self.assertIn("idx_message_reactions_message", indexes)
        self.assertIn("idx_pinned_messages_conversation", indexes)

        self.db.execute(
            """INSERT INTO message_reactions
               (scope_type, scope_id, message_id, user_id, emoji)
               VALUES ('private', 'u1:u2', 'm1', 'u1', '❤️')"""
        )
        self.db.execute(
            """INSERT OR IGNORE INTO message_reactions
               (scope_type, scope_id, message_id, user_id, emoji)
               VALUES ('private', 'u1:u2', 'm1', 'u1', '❤️')"""
        )
        self.db.execute(
            """INSERT INTO message_reactions
               (scope_type, scope_id, message_id, user_id, emoji)
               VALUES ('private', 'u1:u2', 'm1', 'u2', '❤️')"""
        )
        self.assertEqual(
            self.db.execute("SELECT COUNT(*) FROM message_reactions").fetchone()[0],
            2,
        )

        self.db.execute(
            """INSERT INTO pinned_messages
               (scope_type, scope_id, message_id, pinned_by)
               VALUES ('private', 'u1:u2', 'm1', 'u1')"""
        )
        self.db.execute(
            """INSERT OR IGNORE INTO pinned_messages
               (scope_type, scope_id, message_id, pinned_by)
               VALUES ('private', 'u1:u2', 'm1', 'u1')"""
        )
        self.db.execute(
            """INSERT INTO pinned_messages
               (scope_type, scope_id, message_id, pinned_by)
               VALUES ('private', 'u1:u2', 'm1', 'u2')"""
        )
        self.assertEqual(
            self.db.execute("SELECT COUNT(*) FROM pinned_messages").fetchone()[0],
            2,
        )
        self.db.execute(
            """DELETE FROM pinned_messages
               WHERE scope_type = 'private' AND scope_id = 'u1:u2'
                 AND message_id = 'm1' AND pinned_by = 'u1'"""
        )
        self.assertEqual(
            self.db.execute("SELECT pinned_by FROM pinned_messages").fetchall(),
            [("u2",)],
        )


if __name__ == "__main__":
    unittest.main()

    def test_preview_group_roles_are_limited_and_cascade_with_membership(self):
        self.db.execute(
            "INSERT INTO users (id, username, display_name, password_hash, password_salt) VALUES ('owner', 'groupowner', 'Owner', 'hash', 'salt')"
        )
        self.db.execute(
            "INSERT INTO users (id, username, display_name, password_hash, password_salt) VALUES ('admin', 'groupadmin', 'Admin', 'hash', 'salt')"
        )
        self.db.execute(
            "INSERT INTO users (id, username, display_name, password_hash, password_salt) VALUES ('member', 'groupmember', 'Member', 'hash', 'salt')"
        )
        self.db.execute(
            "INSERT INTO chat_groups (id, name, owner_id) VALUES ('g1', 'Group', 'owner')"
        )
        self.db.executemany(
            "INSERT INTO group_members (group_id, user_id) VALUES ('g1', ?)",
            [('owner',), ('admin',), ('member',)],
        )
        self.db.execute(
            "INSERT INTO group_member_roles (group_id, user_id, role) VALUES ('g1', 'admin', 'admin')"
        )
        self.assertEqual(
            self.db.execute(
                "SELECT role FROM group_member_roles WHERE group_id = 'g1' AND user_id = 'admin'"
            ).fetchone()[0],
            "admin",
        )
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                "INSERT INTO group_member_roles (group_id, user_id, role) VALUES ('g1', 'member', 'owner')"
            )
        self.db.execute(
            "DELETE FROM group_members WHERE group_id = 'g1' AND user_id = 'admin'"
        )
        self.assertIsNone(
            self.db.execute(
                "SELECT role FROM group_member_roles WHERE group_id = 'g1' AND user_id = 'admin'"
            ).fetchone()
        )
