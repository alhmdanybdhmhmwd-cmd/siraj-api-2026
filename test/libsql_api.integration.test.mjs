import test from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@libsql/client";
import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import worker from "../src/src/index.js";
import { createLibsqlDatabaseProvider } from "../src/src/runtime_adapters.js";

test("BARQ account registration, contact creation, and idempotent chat work through the real Worker on libSQL", async () => {
  const directory = mkdtempSync(join(tmpdir(), "barq-api-libsql-"));
  const client = createClient({ url: `file:${join(directory, "barq-api.db")}` });
  const db = createLibsqlDatabaseProvider(client);
  const traceStatement = (statement, sql) => ({
    bind(...args) { return traceStatement(statement.bind(...args), sql); },
    async first() {
      try { return await statement.first(); }
      catch (error) { console.error("LIBSQL_SQL_ERROR", sql, error?.message); throw error; }
    },
    async all() {
      try { return await statement.all(); }
      catch (error) { console.error("LIBSQL_SQL_ERROR", sql, error?.message); throw error; }
    },
    async run() {
      try { return await statement.run(); }
      catch (error) { console.error("LIBSQL_SQL_ERROR", sql, error?.message); throw error; }
    }
  });
  const tracedDb = {
    prepare(sql) { return traceStatement(db.prepare(sql), sql); },
    async batch(statements) {
      try { return await db.batch(statements); }
      catch (error) {
        console.error("LIBSQL_BATCH_ERROR", statements.map(item => item.sql), error?.message);
        throw error;
      }
    },
    exec(sql) { return db.exec(sql); }
  };
  const env = { DB: tracedDb, JWT_SECRET: "barq-integration-test-secret-not-for-production" };
  const ctx = { waitUntil() {} };

  const request = async (path, method = "GET", body, token) => {
    const headers = {};
    if (body !== undefined) headers["Content-Type"] = "application/json";
    if (token) headers.Authorization = `Bearer ${token}`;
    return worker.fetch(new Request(`https://barq.integration.test${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body)
    }), env, ctx);
  };

  try {
    const migrationsDirectory = resolve("migrations");
    const migrations = readdirSync(migrationsDirectory)
      .filter(name => name.endsWith(".sql"))
      .sort();
    for (const migration of migrations) {
      await db.exec(readFileSync(join(migrationsDirectory, migration), "utf8"));
    }

    const firstRegistration = await request("/api/register", "POST", {
      displayName: "BARQ One",
      username: "api_barq_one",
      phone: "+12025550101",
      password: "Barq-Test-Password-1"
    });
    const firstRegistrationBody = await firstRegistration.text();
    assert.equal(firstRegistration.status, 201, `registration failed: ${firstRegistrationBody}`);
    const first = JSON.parse(firstRegistrationBody);
    assert.ok(first.user.id);
    assert.ok(first.token);

    const secondRegistration = await request("/api/register", "POST", {
      displayName: "BARQ Two",
      username: "api_barq_two",
      phone: "+12025550102",
      password: "Barq-Test-Password-2"
    });
    assert.equal(secondRegistration.status, 201);
    const second = await secondRegistration.json();

    const contactResponse = await request(
      "/api/contacts",
      "POST",
      { userId: second.user.id },
      first.token
    );
    assert.equal(contactResponse.status, 201);

    const messagePayload = {
      receiverId: second.user.id,
      body: "Hello through libSQL",
      clientMessageId: "0123456789abcdef0123456789abcdef"
    };
    const sentResponse = await request("/api/messages", "POST", messagePayload, first.token);
    assert.equal(sentResponse.status, 201);
    const sent = await sentResponse.json();
    assert.equal(sent.id, messagePayload.clientMessageId);

    const retryResponse = await request("/api/messages", "POST", messagePayload, first.token);
    assert.equal(retryResponse.status, 200);
    const retry = await retryResponse.json();
    assert.equal(retry.duplicate, true);

    const historyResponse = await request(
      `/api/messages?with=${encodeURIComponent(first.user.id)}`,
      "GET",
      undefined,
      second.token
    );
    assert.equal(historyResponse.status, 200);
    const history = await historyResponse.json();
    assert.equal(history.messages.length, 1);
    assert.equal(history.messages[0].body, "Hello through libSQL");
    assert.equal(history.messages[0].sender_id, first.user.id);

    const stored = await db.prepare(
      "SELECT COUNT(*) AS count FROM messages WHERE id = ?"
    ).bind(messagePayload.clientMessageId).first();
    assert.equal(Number(stored.count), 1);
  } finally {
    client.close();
    rmSync(directory, { recursive: true, force: true });
  }
});
