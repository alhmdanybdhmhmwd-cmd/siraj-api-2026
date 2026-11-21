import test from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@libsql/client";
import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createLibsqlDatabaseProvider } from "../src/src/runtime_adapters.js";

test("real libSQL applies every isolated Preview migration and supports BARQ data operations", async () => {
  const directory = mkdtempSync(join(tmpdir(), "barq-libsql-"));
  const client = createClient({ url: `file:${join(directory, "barq-preview.db")}` });
  const db = createLibsqlDatabaseProvider(client);

  try {
    const migrationsDirectory = resolve("migrations");
    const migrations = readdirSync(migrationsDirectory)
      .filter(name => name.endsWith(".sql"))
      .sort();

    assert.equal(migrations.length, 12, "all 12 Preview migrations must be exercised");

    for (const migration of migrations) {
      const sql = readFileSync(join(migrationsDirectory, migration), "utf8");
      await db.exec(sql);
    }

    // Foreign-key enforcement is connection-scoped in SQLite; enable it on
    // the client connection used by the following integration assertions.
    await client.execute("PRAGMA foreign_keys = ON");

    const tables = await client.execute(
      "SELECT name FROM sqlite_master WHERE type = 'table'"
    );
    const tableNames = new Set(tables.rows.map(row => row.name));
    for (const name of [
      "users", "friendships", "messages", "group_messages",
      "message_reactions", "pinned_messages", "ephemeral_messages",
      "media_upload_sessions", "media_upload_parts", "media_upload_chunks"
    ]) {
      assert.ok(tableNames.has(name), `missing migrated table: ${name}`);
    }

    await db.batch([
      db.prepare("INSERT INTO users (id, username, display_name, password_hash, password_salt) VALUES (?, ?, ?, ?, ?)")
        .bind("u1", "barq_one", "BARQ One", "hash1", "salt1"),
      db.prepare("INSERT INTO users (id, username, display_name, password_hash, password_salt) VALUES (?, ?, ?, ?, ?)")
        .bind("u2", "barq_two", "BARQ Two", "hash2", "salt2")
    ]);

    await db.prepare(
      "INSERT INTO friendships (user_id, friend_id) VALUES (?, ?)"
    ).bind("u1", "u2").run();

    await db.prepare(
      "INSERT INTO messages (id, sender_id, receiver_id, body) VALUES (?, ?, ?, ?)"
    ).bind("msg-1", "u1", "u2", "hello").run();

    await db.prepare(
      "UPDATE messages SET body = ?, edited_at = CURRENT_TIMESTAMP WHERE id = ?"
    ).bind("edited hello", "msg-1").run();

    await db.prepare(
      "INSERT INTO message_reactions (scope_type, scope_id, message_id, user_id, emoji) VALUES (?, ?, ?, ?, ?)"
    ).bind("private", "u1:u2", "msg-1", "u2", "👍").run();

    await db.prepare(
      "INSERT INTO pinned_messages (scope_type, scope_id, message_id, pinned_by) VALUES (?, ?, ?, ?)"
    ).bind("private", "u1:u2", "msg-1", "u1").run();

    await db.prepare(
      "INSERT INTO ephemeral_messages (id, sender_id, receiver_id, body) VALUES (?, ?, ?, ?)"
    ).bind("ephemeral-1", "u1", "u2", "temporary").run();

    const message = await db.prepare(
      "SELECT body, edited_at FROM messages WHERE id = ?"
    ).bind("msg-1").first();
    assert.equal(message.body, "edited hello");
    assert.ok(message.edited_at);

    const counts = await db.prepare(
      "SELECT (SELECT COUNT(*) FROM friendships) AS friendships, (SELECT COUNT(*) FROM message_reactions) AS reactions, (SELECT COUNT(*) FROM pinned_messages) AS pins, (SELECT COUNT(*) FROM ephemeral_messages) AS ephemeral"
    ).first();
    assert.deepEqual(
      [Number(counts.friendships), Number(counts.reactions), Number(counts.pins), Number(counts.ephemeral)],
      [1, 1, 1, 1]
    );

    await assert.rejects(
      () => db.prepare(
        "INSERT INTO friendships (user_id, friend_id) VALUES (?, ?)"
      ).bind("u1", "u2").run(),
      /UNIQUE|unique/
    );

    await assert.rejects(
      () => db.prepare(
        "INSERT INTO messages (id, sender_id, receiver_id, body) VALUES (?, ?, ?, ?)"
      ).bind("bad-fk", "missing-user", "u2", "must fail").run(),
      /FOREIGN KEY|foreign key/
    );
  } finally {
    client.close();
    rmSync(directory, { recursive: true, force: true });
  }
});
