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
  const tracedClient = {
    async execute(statement) {
      try { return await client.execute(statement); }
      catch (error) {
        console.error("LIBSQL_SQL_ERROR", typeof statement === "string" ? statement : statement?.sql, error?.message);
        throw error;
      }
    },
    async batch(statements, mode) {
      try { return await client.batch(statements, mode); }
      catch (error) {
        console.error("LIBSQL_BATCH_ERROR", statements.map(item => item.sql), error?.message);
        throw error;
      }
    },
    executeMultiple(sql) { return client.executeMultiple(sql); }
  };
  const db = createLibsqlDatabaseProvider(tracedClient);
  const env = { DB: db, JWT_SECRET: "barq-integration-test-secret-not-for-production" };
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

    const loginResponse = await request("/api/login", "POST", {
      username: "+12025550101",
      password: "Barq-Test-Password-1"
    });
    assert.equal(loginResponse.status, 200);
    const loggedIn = await loginResponse.json();
    assert.equal(loggedIn.user.id, first.user.id);
    assert.ok(loggedIn.token);

    const searchResponse = await request(
      "/api/users/search?q=api_barq_two",
      "GET",
      undefined,
      first.token
    );
    assert.equal(searchResponse.status, 200);
    const search = await searchResponse.json();
    assert.ok(search.users.some(user => user.id === second.user.id));

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
