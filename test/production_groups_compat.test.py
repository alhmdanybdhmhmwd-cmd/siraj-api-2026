import sqlite3
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migrations" / "production" / "0003_groups_worker_compatibility.sql"


class ProductionGroupsCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys = ON")
        self.db.executescript("""
            CREATE TABLE users (
                id TEXT PRIMARY KEY,
                username TEXT NOT NULL UNIQUE
            );
            CREATE TABLE groups (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                created_by TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE TABLE group_members (
                group_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                role TEXT NOT NULL DEFAULT 'member'
                    CHECK (role IN ('owner', 'admin', 'member')),
                joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (group_id, user_id),
                FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE TABLE messages (
                id TEXT PRIMARY KEY,
                sender_id TEXT NOT NULL,
                receiver_id TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                read_at TEXT,
                FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE TABLE group_messages (
                id TEXT PRIMARY KEY,
                group_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
                FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
            );
            CREATE TABLE media_assets (
                id TEXT PRIMARY KEY,
                owner_id TEXT NOT NULL,
                recipient_id TEXT,
                group_id TEXT,
                object_key TEXT NOT NULL UNIQUE,
                file_name TEXT NOT NULL,
                content_type TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                expires_at TEXT,
                storage_deleted INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE,
                FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
            );
            INSERT INTO users(id, username) VALUES ('owner-1', 'owner1');
            INSERT INTO users(id, username) VALUES ('member-1', 'member1');
            INSERT INTO groups(id, name, description, created_by)
                VALUES ('legacy-group', 'Legacy group', 'kept', 'owner-1');
            INSERT INTO group_members(group_id, user_id)
                VALUES ('legacy-group', 'owner-1');
            INSERT INTO messages(id, sender_id, receiver_id, body)
                VALUES ('legacy-private-message', 'owner-1', 'member-1', 'private survives');
            INSERT INTO group_messages(id, group_id, sender_id, body)
                VALUES ('legacy-message', 'legacy-group', 'owner-1', 'preserve me');
            INSERT INTO media_assets
                (id, owner_id, group_id, object_key, file_name, content_type, size_bytes)
                VALUES ('legacy-media', 'owner-1', 'legacy-group',
                        'private/legacy', 'legacy.jpg', 'image/jpeg', 12);
        """)

    def tearDown(self):
        self.db.close()

    def test_existing_production_group_data_survives_and_worker_view_writes(self):
        self.db.executescript(MIGRATION.read_text(encoding="utf-8"))

        # Existing production records are exposed through the Worker's chat_groups contract.
        legacy = self.db.execute(
            "SELECT id, name, owner_id FROM chat_groups WHERE id = 'legacy-group'"
        ).fetchone()
        self.assertEqual(legacy, ("legacy-group", "Legacy group", "owner-1"))
        self.assertEqual(
            self.db.execute(
                "SELECT body FROM messages WHERE id = 'legacy-private-message'"
            ).fetchone()[0],
            "private survives",
        )
        self.assertEqual(
            self.db.execute(
                "SELECT body FROM group_messages WHERE id = 'legacy-message'"
            ).fetchone()[0],
            "preserve me",
        )
        self.assertEqual(
            self.db.execute(
                "SELECT group_id FROM media_assets WHERE id = 'legacy-media'"
            ).fetchone()[0],
            "legacy-group",
        )

        # Worker INSERT into chat_groups is routed to the existing groups table.
        self.db.execute(
            "INSERT INTO chat_groups (id, name, description, owner_id) "
            "VALUES ('new-group', 'New group', '', 'owner-1')"
        )
        self.db.execute(
            "INSERT INTO group_members (group_id, user_id) VALUES ('new-group', 'owner-1')"
        )
        self.db.execute(
            """INSERT INTO group_messages
               (id, group_id, sender_id, body, reply_to_id, reply_to_body,
                reply_to_sender_id)
               VALUES ('new-message', 'new-group', 'owner-1', 'reply',
                       'legacy-message', 'preserve me', 'owner-1')"""
        )
        update_cursor = self.db.execute(
            "UPDATE chat_groups SET owner_id = 'member-1' WHERE id = 'new-group'"
        )
        # SQLite reports zero affected rows for INSTEAD OF-triggered view writes,
        # although the underlying groups row was updated. The Worker must verify
        # the resulting owner by reading the view, not by checking meta.changes.
        self.assertEqual(update_cursor.rowcount, 0)

        self.assertEqual(
            self.db.execute(
                "SELECT created_by FROM groups WHERE id = 'new-group'"
            ).fetchone()[0],
            "member-1",
        )
        self.assertEqual(
            self.db.execute(
                "SELECT reply_to_id, reply_to_body, reply_to_sender_id "
                "FROM group_messages WHERE id = 'new-message'"
            ).fetchone(),
            ("legacy-message", "preserve me", "owner-1"),
        )
        self.db.execute(
            "UPDATE group_messages SET body = 'edited', edited_at = CURRENT_TIMESTAMP "
            "WHERE id = 'new-message'"
        )
        self.db.execute(
            "UPDATE messages SET body = 'private edited', edited_at = CURRENT_TIMESTAMP "
            "WHERE id = 'legacy-private-message'"
        )
        self.assertEqual(
            self.db.execute(
                "SELECT reply_to_id, reply_to_body, reply_to_sender_id "
                "FROM messages WHERE id = 'legacy-private-message'"
            ).fetchone(),
            (None, None, None),
        )
        self.assertEqual(
            self.db.execute(
                "SELECT body FROM messages WHERE id = 'legacy-private-message'"
            ).fetchone()[0],
            "private edited",
        )
        self.assertEqual(
            self.db.execute(
                "SELECT body, edited_at FROM group_messages WHERE id = 'new-message'"
            ).fetchone()[0],
            "edited",
        )
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_admin_role_is_scoped_to_an_existing_membership(self):
        self.db.executescript(MIGRATION.read_text(encoding="utf-8"))
        self.db.execute(
            "INSERT INTO group_member_roles(group_id, user_id, role) "
            "VALUES ('legacy-group', 'owner-1', 'admin')"
        )
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(
                "INSERT INTO group_member_roles(group_id, user_id, role) "
                "VALUES ('legacy-group', 'member-1', 'admin')"
            )
        self.db.execute(
            "DELETE FROM group_members WHERE group_id = 'legacy-group' AND user_id = 'owner-1'"
        )
        self.assertEqual(
            self.db.execute("SELECT COUNT(*) FROM group_member_roles").fetchone()[0],
            0,
        )


if __name__ == "__main__":
    unittest.main()
