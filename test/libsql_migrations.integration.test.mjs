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


test("real libSQL upgrades an existing chat database without losing account or attachment records", async () => {
  const directory = mkdtempSync(join(tmpdir(), "barq-libsql-upgrade-"));
  const client = createClient({ url: `file:${join(directory, "barq-upgrade.db")}` });
  const db = createLibsqlDatabaseProvider(client);

  try {
    const migrationsDirectory = resolve("migrations");
    const migrations = readdirSync(migrationsDirectory)
      .filter(name => name.endsWith(".sql"))
      .sort();

    // Build the original core schema and seed pre-upgrade application data.
    for (const migration of migrations.slice(0, 3)) {
      await db.exec(readFileSync(join(migrationsDirectory, migration), "utf8"));
    }
    await client.execute("PRAGMA foreign_keys = ON");

    await db.batch([
      db.prepare("INSERT INTO users (id, username, display_name, password_hash, password_salt) VALUES (?, ?, ?, ?, ?)")
        .bind("legacy-u1", "legacy_one", "Legacy One", "hash1", "salt1"),
      db.prepare("INSERT INTO users (id, username, display_name, password_hash, password_salt) VALUES (?, ?, ?, ?, ?)")
        .bind("legacy-u2", "legacy_two", "Legacy Two", "hash2", "salt2")
    ]);

    const attachmentBody = JSON.stringify({
      type: "attachment",
      attachmentId: "legacy-object-1",
      fileName: "legacy.png"
    });
    await db.prepare(
      "INSERT INTO messages (id, sender_id, receiver_id, body) VALUES (?, ?, ?, ?)"
    ).bind("legacy-msg-1", "legacy-u1", "legacy-u2", attachmentBody).run();

    // These two tables represent the pre-existing attachment authorization
    // records consumed by migration 0012.
    await db.exec(`
      CREATE TABLE media_expirations (
        object_key TEXT PRIMARY KEY,
        expires_at TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE media_access (
        object_key TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        recipient_id TEXT,
        group_id TEXT,
        file_name TEXT NOT NULL,
        content_type TEXT NOT NULL,
        expires_at TEXT NOT NULL
      );
    `);
    await db.prepare(
      "INSERT INTO media_access (object_key, owner_id, recipient_id, file_name, content_type, expires_at) VALUES (?, ?, ?, ?, ?, ?)"
    ).bind("legacy-object-1", "legacy-u1", "legacy-u2", "legacy.png", "image/png", "2026-12-01T00:00:00.000Z").run();
    await db.prepare(
      "INSERT INTO media_expirations (object_key, expires_at) VALUES (?, ?)"
    ).bind("legacy-object-1", "2026-12-01T00:00:00.000Z").run();

    // Apply all remaining schema upgrades in order.
    for (const migration of migrations.slice(3)) {
      await db.exec(readFileSync(join(migrationsDirectory, migration), "utf8"));
    }

    const preserved = await db.prepare(
      "SELECT m.body, u.username FROM messages m JOIN users u ON u.id = m.sender_id WHERE m.id = ?"
    ).bind("legacy-msg-1").first();
    assert.equal(preserved.username, "legacy_one");
    assert.equal(JSON.parse(preserved.body).attachmentId, "legacy-object-1");

    const access = await db.prepare(
      "SELECT expires_at FROM media_access WHERE object_key = ?"
    ).bind("legacy-object-1").first();
    assert.equal(access.expires_at, "9999-12-31T23:59:59.999Z");

    const expiry = await db.prepare(
      "SELECT COUNT(*) AS count FROM media_expirations WHERE object_key = ?"
    ).bind("legacy-object-1").first();
    assert.equal(Number(expiry.count), 0);

    const editColumns = await client.execute("PRAGMA table_info(messages)");
    assert.ok(editColumns.rows.some(row => row.name === "edited_at"));
    assert.ok(editColumns.rows.some(row => row.name === "reply_to_id"));
  } finally {
    client.close();
    rmSync(directory, { recursive: true, force: true });
  }
});
