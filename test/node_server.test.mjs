import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createNodeApiServer, createNodeEnvironment, startNodeApiServer } from "../node_server.mjs";

const silentLogger = { log() {}, error() {} };

async function withServer(fetchHandler, run) {
  const server = createNodeApiServer({
    env: { DB: { prepare() {} } },
    fetchHandler,
    logger: silentLogger
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  try {
    await run("http://127.0.0.1:" + address.port);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

test("standalone environment requires a database URL and JWT secret", () => {
  assert.throws(() => createNodeEnvironment({ JWT_SECRET: "test" }), /LIBSQL_URL/);
  assert.throws(() => createNodeEnvironment({ LIBSQL_URL: "file:barq.db" }), /JWT_SECRET/);
  const env = createNodeEnvironment(
    { JWT_SECRET: "test-secret" },
    { DB: { prepare() {} } }
  );
  assert.equal(env.JWT_SECRET, "test-secret");
  assert.equal(env.DB != null, true);
  assert.equal(env.AI, null);
});

test("Node HTTP adapter forwards method, auth, range and binary request body", async () => {
  let observed;
  await withServer(async (request) => {
    observed = {
      method: request.method,
      authorization: request.headers.get("authorization"),
      range: request.headers.get("range"),
      body: new Uint8Array(await request.arrayBuffer())
    };
    return new Response(new Uint8Array([0, 255, 12]), {
      status: 206,
      headers: {
        "Content-Type": "application/octet-stream",
        "Content-Range": "bytes 0-2/9",
        "Accept-Ranges": "bytes"
      }
    });
  }, async base => {
    const response = await fetch(base + "/api/media/test", {
      method: "PUT",
      headers: {
        Authorization: "Bearer test-token",
        Range: "bytes=0-2",
        "Content-Type": "application/octet-stream"
      },
      body: new Uint8Array([4, 5, 6])
    });
    assert.equal(response.status, 206);
    assert.equal(response.headers.get("content-range"), "bytes 0-2/9");
    assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [0, 255, 12]);
  });
  assert.equal(observed.method, "PUT");
  assert.equal(observed.authorization, "Bearer test-token");
  assert.equal(observed.range, "bytes=0-2");
  assert.deepEqual([...observed.body], [4, 5, 6]);
});

test("standalone adapter preserves HEAD and OPTIONS behavior", async () => {
  const methods = [];
  await withServer(async request => {
    methods.push(request.method);
    return new Response(null, { status: request.method === "OPTIONS" ? 204 : 200 });
  }, async base => {
    const head = await fetch(base + "/health/live", { method: "HEAD" });
    const options = await fetch(base + "/api/auth/login", { method: "OPTIONS" });
    assert.equal(head.status, 200);
    assert.equal(options.status, 204);
  });
  assert.deepEqual(methods, ["HEAD", "OPTIONS"]);
});


test("standalone server refuses startup when its database readiness probe fails", async () => {
  await assert.rejects(
    () => startNodeApiServer({
      env: { DB: { async healthCheck() { return false; } } },
      disableScheduler: true,
      logger: silentLogger
    }),
    /database readiness check failed/
  );
});

test("standalone HTTP adapter can serve the real Worker liveness route", async () => {
  await withServer(undefined, async base => {
    const response = await fetch(base + "/health/live");
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: "alive", service: "barq-api" });
  });
});


test("standalone Node API serves real Worker readiness over a local libSQL database", async () => {
  const directory = await mkdtemp(join(tmpdir(), "barq-node-api-"));
  let instance;
  try {
    const env = createNodeEnvironment({
      LIBSQL_URL: "file:" + join(directory, "barq-test.db"),
      JWT_SECRET: "isolated-node-api-test-secret"
    });
    instance = await startNodeApiServer({
      env,
      port: 0,
      host: "127.0.0.1",
      disableScheduler: true,
      logger: silentLogger
    });
    const base = "http://127.0.0.1:" + instance.port;
    const live = await fetch(base + "/health/live");
    const ready = await fetch(base + "/health/ready");
    assert.equal(live.status, 200);
    assert.deepEqual(await live.json(), { status: "alive", service: "barq-api" });
    assert.equal(ready.status, 200);
    assert.deepEqual(await ready.json(), { status: "ready", service: "barq-api" });
  } finally {
    await instance?.close();
    await rm(directory, { recursive: true, force: true });
  }
});
