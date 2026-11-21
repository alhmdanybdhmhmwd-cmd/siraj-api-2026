import test from "node:test";
import assert from "node:assert/strict";
import {
  createAiProvider,
  createDatabaseProvider,
  createLibsqlDatabaseProvider,
  createObjectStorageClient,
  createObjectStorageProvider,
  createS3ObjectStorageProvider,
  createObjectStorageUrl,
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
  assert.throws(() => db.prepare(""), /SQL statement is required/);

  // An alternate runtime can inject the same narrow SQL capability contract.
  const alternateCalls = [];
  const alternate = createDatabaseProvider({
    prepare(sql) {
      const statement = {
        first: async () => ({ barq_ready: 1 }),
        bind(...params) {
          alternateCalls.push({ sql, params });
          return {
            first: async () => ({ barq_ready: 1 }),
            all: async () => ({ results: [] }),
            run: async () => ({ success: true })
          };
        }
      };
      return statement;
    },
    batch: async statements => statements.map(() => ({ success: true })),
    exec: async sql => ({ success: true, sql })
  });
  assert.equal(await alternate.healthCheck(), true);
  const statement = alternate.prepare("SELECT ? AS value").bind(7);
  assert.deepEqual(await statement.first(), { barq_ready: 1 });
  assert.deepEqual(await statement.all(), { results: [] });
  assert.deepEqual(await statement.run(), { success: true });
  assert.equal(alternateCalls[0].sql, "SELECT ? AS value");
  assert.deepEqual(alternateCalls[0].params, [7]);

  const limited = createDatabaseProvider({ prepare: sql => ({ sql }) });
  await assert.rejects(() => limited.batch([]), /not supported/);
  await assert.rejects(() => limited.exec("SELECT 1"), /not supported/);
});

test("libSQL adapter exposes D1-compatible prepared statements and atomic batches", async () => {
  const calls = [];
  const client = {
    async execute(statement) {
      calls.push(["execute", statement]);
      if (statement === "SELECT 1 AS barq_ready" || statement.sql === "SELECT 1 AS barq_ready") {
        return { rows: [{ barq_ready: 1 }] };
      }
      return { rows: [{ value: statement.args?.[0] ?? null }], rowsAffected: 1 };
    },
    async batch(statements, mode) {
      calls.push(["batch", statements, mode]);
      return statements.map(() => ({ rowsAffected: 1 }));
    },
    async executeMultiple(sql) {
      calls.push(["executeMultiple", sql]);
      return { ok: true };
    }
  };
  const db = createLibsqlDatabaseProvider(client);
  assert.equal(await db.healthCheck(), true);
  const statement = db.prepare("SELECT ? AS value").bind(42);
  assert.deepEqual(await statement.first(), { value: 42 });
  assert.deepEqual((await statement.all()).results, [{ value: 42 }]);
  const runResult = await statement.run();
  assert.equal(runResult.success, true);
  assert.equal(runResult.meta.changes, 1);
  const batch = await db.batch([
    db.prepare("INSERT INTO messages(id) VALUES (?)").bind("m1"),
    db.prepare("INSERT INTO messages(id) VALUES (?)").bind("m2")
  ]);
  assert.equal(batch.length, 2);
  assert.equal(batch[0].meta.changes, 1);
  assert.equal(calls.find(call => call[0] === "batch")[2], "write");
  assert.deepEqual(calls.find(call => call[0] === "batch")[1].map(item => item.args), [["m1"], ["m2"]]);
  assert.deepEqual(await db.exec("CREATE TABLE sample(id TEXT)"), { ok: true });
  await assert.rejects(() => db.batch([{}]), /prepared by this provider/);
  assert.throws(() => createLibsqlDatabaseProvider({}), /execute and batch/);

  const singleStatementOnlyClient = {
    async execute() { return { rows: [] }; },
    async batch() { return []; }
  };
  const limitedDb = createLibsqlDatabaseProvider(singleStatementOnlyClient);
  await assert.rejects(
    () => limitedDb.exec("CREATE TABLE a(id INTEGER); CREATE TABLE b(id INTEGER);"),
    /executeMultiple is required/
  );
});

test("object storage URLs preserve Tigris defaults and support generic S3 endpoints", () => {
  assert.equal(
    createObjectStorageUrl({ TIGRIS_BUCKET: "barq-media" }, "users/u1/profile photo.png"),
    "https://barq-media.t3.storage.dev/users/u1/profile%20photo.png"
  );
  assert.equal(
    createObjectStorageUrl({ OBJECT_STORAGE_BUCKET: "barq-media", OBJECT_STORAGE_ENDPOINT: "https://{bucket}.objects.example" }, "chat/a+b.png", { versionId: "v1" }),
    "https://barq-media.objects.example/chat/a%2Bb.png?versionId=v1"
  );
  assert.equal(
    createObjectStorageUrl({ OBJECT_STORAGE_BUCKET: "barq-media", OBJECT_STORAGE_ENDPOINT: "https://objects.example/s3" }, "chat/file.bin"),
    "https://objects.example/s3/barq-media/chat/file.bin"
  );
  assert.throws(() => createObjectStorageUrl({}, "/absolute/key"), /safe relative object key/);
  assert.throws(() => createObjectStorageUrl({}, "../private/file"), /safe relative object key/);
  assert.throws(() => createObjectStorageUrl({}, "folder\\file"), /safe relative object key/);
});

test("object storage provider exposes neutral get put delete head post and request operations", async () => {
  const calls = [];
  const provider = createObjectStorageProvider({
    urlFor: (key, query = {}) => {
      const url = new URL("https://objects.example/bucket/" + key);
      for (const [name, value] of Object.entries(query)) url.searchParams.set(name, String(value));
      return url.toString();
    },
    request: async (url, init) => {
      calls.push({ url, init });
      return new Response("ok", { status: 200 });
    }
  });
  await provider.get("a.png");
  await provider.put("b.png", "bytes", { "Content-Type": "image/png" });
  await provider.delete("c.png", { uploadId: "upload-1" });
  await provider.head("d.png");
  await provider.post("e.png", "<xml>", { "Content-Type": "application/xml" }, { uploads: "" });
  await provider.request("f.png", { method: "PATCH" }, { versionId: "v1" });
  await provider.fetchUrl("https://signed.example/existing-object?signature=kept", { method: "GET" });
  assert.equal(calls[6].url, "https://signed.example/existing-object?signature=kept");
  assert.equal(calls[6].init.method, "GET");
  assert.deepEqual(calls.map(call => new URL(call.url).pathname), [
    "/bucket/a.png", "/bucket/b.png", "/bucket/c.png", "/bucket/d.png", "/bucket/e.png", "/bucket/f.png", "/existing-object"
  ]);
  assert.deepEqual(calls.map(call => call.init.method), ["GET", "PUT", "DELETE", "HEAD", "POST", "PATCH", "GET"]);
  assert.equal(new URL(calls[2].url).searchParams.get("uploadId"), "upload-1");
  assert.equal(new URL(calls[4].url).searchParams.has("uploads"), true);
  assert.equal(new URL(calls[5].url).searchParams.get("versionId"), "v1");
  assert.equal(calls[1].init.body, "bytes");
});

test("S3 provider adapts the runtime signer behind the neutral storage contract", async () => {
  const requests = [];
  class FakeSigner {
    constructor(config) { this.config = config; }
    async fetch(url, init) { requests.push({ url, init }); return new Response("stored"); }
  }
  const provider = createS3ObjectStorageProvider({
    TIGRIS_ACCESS_KEY_ID: "access",
    TIGRIS_SECRET_ACCESS_KEY: "secret",
    TIGRIS_BUCKET: "barq-media"
  }, FakeSigner);
  const response = await provider.put("chat/file.bin", new Uint8Array([1, 2]), { "Content-Type": "application/octet-stream" });
  assert.equal(await response.text(), "stored");
  assert.equal(new URL(requests[0].url).hostname, "barq-media.t3.storage.dev");
  assert.equal(requests[0].init.method, "PUT");
  assert.equal(provider.delete instanceof Function, true);
});

test("object storage client uses the common S3-compatible configuration", () => {
  class FakeClient { constructor(options) { this.options = options; } }
  const client = createObjectStorageClient({
    OBJECT_STORAGE_ACCESS_KEY_ID: "access",
    OBJECT_STORAGE_SECRET_ACCESS_KEY: "secret",
    OBJECT_STORAGE_REGION: "us-east-1"
  }, FakeClient);
  assert.deepEqual(client.options, {
    accessKeyId: "access",
    secretAccessKey: "secret",
    service: "s3",
    region: "us-east-1",
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
