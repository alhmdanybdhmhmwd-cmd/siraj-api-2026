import test from "node:test";
import assert from "node:assert/strict";
import {
  createAiProvider,
  createDatabaseProvider,
  createObjectStorageClient,
  createPushProvider,
  createBackgroundTaskScheduler
} from "../src/src/runtime_adapters.js";

test("AI provider preserves the binding context and fails closed when absent", async () => {
  const binding = { marker: "bound", async run(model, input) { return { marker: this.marker, model, input }; } };
  const provider = createAiProvider(binding);
  assert.equal(provider.isAvailable(), true);
  assert.deepEqual(await provider.run("model-a", { prompt: "hello" }), {
    marker: "bound", model: "model-a", input: { prompt: "hello" }
  });
  assert.equal(createAiProvider(null).isAvailable(), false);
  await assert.rejects(() => createAiProvider(null).run("model-a", {}), /not configured/);
});

test("database provider exposes the supported SQL operations", async () => {
  const calls = [];
  const binding = {
    prepare(sql) { calls.push(["prepare", sql]); return { first: async () => ({ barq_ready: 1 }) }; },
    batch(items) { calls.push(["batch", items]); return items; },
    exec(sql) { calls.push(["exec", sql]); return sql; }
  };
  const db = createDatabaseProvider(binding);
  assert.equal(await db.healthCheck(), true);
  assert.deepEqual(await db.batch(["statement"]), ["statement"]);
  assert.equal(await db.exec("SELECT 1"), "SELECT 1");
  assert.equal(calls[0][0], "prepare");
  assert.equal(createDatabaseProvider(null), null);
});

test("object storage client uses the common S3-compatible configuration", () => {
  class FakeClient { constructor(options) { this.options = options; } }
  const client = createObjectStorageClient({
    TIGRIS_ACCESS_KEY_ID: "access",
    TIGRIS_SECRET_ACCESS_KEY: "secret"
  }, FakeClient);
  assert.deepEqual(client.options, {
    accessKeyId: "access",
    secretAccessKey: "secret",
    service: "s3",
    region: "auto",
    retries: 2
  });
  assert.throws(() => createObjectStorageClient({}, FakeClient), /credentials are not configured/);
});

test("push provider delegates requests to the injected transport", async () => {
  const calls = [];
  const provider = createPushProvider(async (url, init) => {
    calls.push({ url, init });
    return new Response("ok", { status: 200 });
  });
  const response = await provider.request("https://push.example/send", { method: "POST" });
  assert.equal(response.status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://push.example/send");
  assert.throws(() => createPushProvider(null), /fetch-compatible/);
});

test("background scheduler registers tasks only when waitUntil is available", async () => {
  let registered;
  const scheduler = createBackgroundTaskScheduler({
    waitUntil(promise) { registered = promise; }
  });
  let ran = false;
  assert.equal(scheduler.schedule(async () => { ran = true; }), true);
  await registered;
  assert.equal(ran, true);
  assert.equal(createBackgroundTaskScheduler(null).schedule(async () => {}), false);
  assert.throws(() => scheduler.schedule(null), /must be a function/);
});
