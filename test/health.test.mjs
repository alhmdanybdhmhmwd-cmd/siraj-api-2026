import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const workerPath = new URL("../src/src/index.js", import.meta.url);
let workerSource = await readFile(workerPath, "utf8");
workerSource = workerSource.replace('import { AwsClient } from "aws4fetch";', 'class AwsClient {}');
const workerModule = await import(
  "data:text/javascript;base64," + Buffer.from(workerSource).toString("base64")
);
const fetchWorker = workerModule.default.fetch;

function request(path) {
  return new Request("https://barq.test" + path, { method: "GET" });
}

test("GET /health/live succeeds without database or secrets", async () => {
  const response = await fetchWorker(request("/health/live"), {});
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "alive", service: "barq-api" });
});

test("GET /health/ready returns 503 when required configuration is missing", async () => {
  const noDatabase = await fetchWorker(request("/health/ready"), { JWT_SECRET: "test" });
  assert.equal(noDatabase.status, 503);
  assert.deepEqual(await noDatabase.json(), { status: "not_ready" });

  const noSecret = await fetchWorker(request("/health/ready"), {
    DB: { prepare() { throw new Error("DB must not be queried"); } }
  });
  assert.equal(noSecret.status, 503);
  assert.deepEqual(await noSecret.json(), { status: "not_ready" });
});

test("GET /health/ready performs only a read-only SELECT probe", async () => {
  const statements = [];
  const env = {
    JWT_SECRET: "unit-test-secret",
    DB: {
      prepare(sql) {
        statements.push(sql);
        return { async first() { return { ok: 1 }; } };
      }
    }
  };
  const response = await fetchWorker(request("/health/ready"), env);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ready", service: "barq-api" });
  assert.deepEqual(statements, ["SELECT 1 AS ok"]);
  assert.ok(statements.every(sql => /^\s*SELECT\b/i.test(sql)));
});

test("GET /health/ready returns 503 when the database probe fails", async () => {
  const env = {
    JWT_SECRET: "unit-test-secret",
    DB: { prepare() { throw new Error("simulated unavailable database"); } }
  };
  const response = await fetchWorker(request("/health/ready"), env);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { status: "not_ready" });
});
