import test from "node:test";
import assert from "node:assert/strict";
import { createAiProvider, createDatabaseProvider } from "./runtime_adapters.js";

test("AI adapter reports unavailable when no provider is configured", async () => {
  const provider = createAiProvider(null);
  assert.equal(provider.isAvailable(), false);
  await assert.rejects(provider.run("model", {}), /not configured/);
});

test("AI adapter preserves provider model, input, and result", async () => {
  const expected = { text: "hello" };
  const calls = [];
  const provider = createAiProvider({
    async run(model, input) {
      calls.push({ model, input });
      return expected;
    }
  });
  const input = { messages: [{ role: "user", content: "hello" }] };
  assert.equal(provider.isAvailable(), true);
  assert.equal(await provider.run("summary-model", input), expected);
  assert.deepEqual(calls, [{ model: "summary-model", input }]);
});

test("AI adapter binds provider method receiver", async () => {
  const binding = {
    marker: "bound",
    async run() { return this.marker; }
  };
  assert.equal(await createAiProvider(binding).run("model", {}), "bound");
});


test("database adapter exposes the BARQ SQL capability contract", async () => {
  const calls = [];
  const binding = {
    prepare(sql) {
      calls.push(["prepare", sql]);
      return {
        bind(...values) {
          calls.push(["bind", values]);
          return this;
        },
        async first() { return { barq_ready: 1 }; },
        async all() { return { results: [] }; },
        async run() { return { success: true }; }
      };
    },
    async batch(statements) { calls.push(["batch", statements.length]); return []; },
    async exec(sql) { calls.push(["exec", sql]); return { success: true }; }
  };
  const db = createDatabaseProvider(binding);
  assert.ok(db);
  assert.equal(await db.healthCheck(), true);
  await db.prepare("SELECT ?").bind(7).first();
  await db.batch([{}, {}]);
  await db.exec("CREATE TABLE test (id INTEGER)");
  assert.deepEqual(calls, [
    ["prepare", "SELECT 1 AS barq_ready"],
    ["prepare", "SELECT ?"],
    ["bind", [7]],
    ["batch", 2],
    ["exec", "CREATE TABLE test (id INTEGER)"]
  ]);
});

test("database adapter fails closed when no SQL provider is configured", () => {
  assert.equal(createDatabaseProvider(null), null);
  assert.equal(createDatabaseProvider({}), null);
});
